-- src/lib/id_generator.lua
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
    self.segment_size = opts.segment_size or 1000
    assert(type(self.segment_size) == "number" and self.segment_size >= 1 and
        self.segment_size <= 1000000 and self.segment_size == math.floor(self.segment_size), "invalid segment size")
    self.sequence_table = opts.sequence_table or "sl_id_sequence"
    self.segment_start = nil
    self.segment_end = nil
    self.cursor = nil
    return self
end

--- 分配新号段 / Allocate a new segment from PostgreSQL
-- 使用原子 UPDATE ... RETURNING 保证多 Worker 安全
-- @return true or nil, err
function _M:_allocate_segment()
    local sql = "UPDATE " .. self.sequence_table ..
        " SET current_max = current_max + $1 WHERE id = 1 AND current_max <= 4294967295 - $1" ..
        " RETURNING (current_max - $1 + 1)::text AS segment_start, current_max::text AS segment_end"
    local res, err = self.db:query(sql, self.segment_size)
    if not res then
        return nil, "failed to allocate segment: " .. tostring(err)
    end
    if not res[1] then
        return nil, "sequence missing or short-code ID space exhausted"
    end
    local row = res[1]
    self.segment_start = tonumber(row.segment_start) or tonumber(row[1])
    self.segment_end = tonumber(row.segment_end) or tonumber(row[2])
    self.cursor = self.segment_start
    if not self.segment_start or not self.segment_end then
        return nil, "failed to parse segment bounds"
    end
    return true
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
