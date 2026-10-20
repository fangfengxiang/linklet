-- lib/linklet/id/generator.lua
-- 发号器：PostgreSQL 号段批量分配，Worker 本地消耗
-- ID generator: segment-based allocation from PostgreSQL

local setmetatable = setmetatable
local tostring = tostring
local error = error
local type = type

local _M = {}
_M.__index = _M

--- 创建发号器实例 / Create ID generator instance
-- @param opts.db 数据库实例（required）
-- @param opts.segment_size 号段大小（default 1000）
-- @param opts.sequence_table 序列表名（default "sl_id_sequence"）
-- @return id_generator 实例
function _M.new(opts)
    if not opts or not opts.db then
        error("opts.db is required", 2)
    end
    local self = setmetatable({}, _M)
    self.db = opts.db
    self.segment_size = opts.segment_size
    self.sequence_key = opts.sequence_key or 1
    assert(type(self.sequence_key)=="number" and self.sequence_key>=1 and
        self.sequence_key<=2147483647 and self.sequence_key==math.floor(self.sequence_key), "invalid sequence key")
    assert(self.segment_size == nil or (type(self.segment_size) == "number" and self.segment_size >= 1 and
        self.segment_size <= 1000000 and self.segment_size == math.floor(self.segment_size)), "invalid segment size")
    self.sequence_table = opts.sequence_table or "sl_id_sequence"
    self.segment_start = nil
    self.segment_end = nil
    self.cursor = nil
    return self
end

--- 分配新号段 / Allocate a new segment from PostgreSQL
-- 使用原子 UPDATE ... RETURNING 保证多 Worker 安全
-- @return true or nil, err
local function valid_size(size)
    return type(size)=="number" and size>=1 and size<=1000000 and size==math.floor(size)
end
function _M:allocate_segment(size)
    if size~=nil and not valid_size(size) then return nil,"invalid segment size" end
    local sql = "UPDATE " .. self.sequence_table .. [[ SET
        current_max=current_max+COALESCE($2::integer,step),updated_at=NOW()
        WHERE sequence_key=$1 AND current_max<=4294967295-COALESCE($2::integer,step)
        RETURNING (current_max-COALESCE($2::integer,step)+1)::text AS segment_start,
        current_max::text AS segment_end]]
    local rows,err=self.db:query(sql,self.sequence_key,size)
    if not rows then return nil,"failed to allocate segment: "..tostring(err) end
    if not rows[1] then return nil,"sequence missing or short-code ID space exhausted" end
    local first,last=tonumber(rows[1].segment_start),tonumber(rows[1].segment_end)
    if not first or not last or first<1 or last<first or last>4294967295 then
        return nil,"failed to parse segment bounds"
    end
    return {start=first,["end"]=last}
end
function _M:_allocate_segment()
    local segment,err=self:allocate_segment(self.segment_size)
    if not segment then return nil,err end
    self.segment_start,self.segment_end,self.cursor=segment.start,segment["end"],segment.start
    return true
end
function _M:next_ids(count)
    if not valid_size(count) then return nil,"invalid count" end
    local ids={}
    for i=1,count do
        local id,err=self:next_id()
        if not id then return nil,err end -- reserved IDs remain consumed on failure
        ids[i]=id
    end
    return ids
end

--- 获取下一个 ID / Get next ID
-- 本地段段耗尽时自动从数据库分配新段
-- @return id 整数 or nil, err
function _M:next_id()
    if self.cursor and self.cursor <= self.segment_end then
        local id = self.cursor
        self.cursor = id + 1
        return id
    end
    -- A worker can yield while reserving a segment. Serialize that path and
    -- recheck after acquiring the semaphore; ordinary local consumption never yields.
    local semaphore
    if ngx and ngx.req then
        if not self.semaphore then
            self.semaphore = assert(require("ngx.semaphore").new(1))
        end
        semaphore = self.semaphore
        local ok, err = semaphore:wait(10)
        if not ok then return nil, err end
    end
    if not self.cursor or self.cursor > self.segment_end then
        local called, ok, err = pcall(self._allocate_segment, self)
        if not called then err, ok = ok, nil end
        if not ok then
            if semaphore then semaphore:post(1) end
            return nil, err
        end
    end
    local id = self.cursor
    self.cursor = id + 1
    if semaphore then semaphore:post(1) end
    return id
end

--- 重置本地段（用于测试）/ Reset local segment (for testing)
function _M:reset()
    self.segment_start = nil
    self.segment_end = nil
    self.cursor = nil
end

--- 获取本地段状态 / Get local segment status
-- @return table {start, end, cursor, remaining}
function _M:status()
    local remaining = 0
    if self.cursor and self.segment_end and self.cursor <= self.segment_end then
        remaining = math.max(0, self.segment_end - self.cursor + 1)
    end
    return {
        start = self.segment_start,
        ["end"] = self.segment_end,
        cursor = self.cursor,
        remaining = remaining,
    }
end

return _M
