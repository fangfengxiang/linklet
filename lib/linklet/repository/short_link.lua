-- lib/linklet/repository/short_link.lua
-- 短链模型：sl_short_link 数据访问
-- Link model: sl_short_link data access

local setmetatable = setmetatable
local tostring = tostring

local Base = require("linklet.repository.base")
local _M = setmetatable({}, {__index = Base})
_M.__index = _M

--- 创建 link 模型实例 / Create link repository instance
function _M.new(db)
    local self = Base.new(db, "sl_short_link")
    return setmetatable(self, _M)
end

--- 按短码查找 / Find link by short code
-- @param code 短码
-- @return row or nil
function _M:find_by_code(code)
    local sql = [[SELECT l.*, EXTRACT(EPOCH FROM l.expires_at) AS expires_epoch,
        d.domain, d.status AS domain_status, d.deleted_at AS domain_deleted_at
        FROM sl_short_link l JOIN sl_group s ON s.group_id=l.group_id
        JOIN sl_domain_entry d ON d.id=s.domain_entry_id
        WHERE l.code=$1 LIMIT 1]]
    local res, err = self.db:query(sql, code)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 创建短链 / Create a short link
-- @param data {code, target_url, group_id, expires_at?}
-- @return row or nil, err
function _M:create(data, tenant_id)
    if not data.code or not data.target_url or not data.group_id then return nil,"missing required fields" end
    return self.db:transaction(function(conn)
        -- Use a fresh snapshot after waiting for a concurrent rebind.
        local locked, lock_err = conn:query("SELECT group_id FROM sl_group WHERE group_id=$1 FOR UPDATE",data.group_id)
        if not locked then return nil, lock_err end
        local sql = [[INSERT INTO sl_short_link(code,target_url,group_id,status,expires_at)
            SELECT $1,$2,s.group_id,1,$4::timestamptz FROM sl_group s
            JOIN sl_domain_entry d ON d.id=s.domain_entry_id
            WHERE s.group_id=$3 AND s.status=1 AND s.deleted_at IS NULL AND d.status=2
            AND d.deleted_at IS NULL AND ($5::bigint IS NULL OR EXISTS(SELECT 1 FROM sl_tenant t
            WHERE t.id=$5 AND t.status=1 AND t.deleted_at IS NULL AND s.group_id=ANY(t.group_ids)))
            RETURNING *, (SELECT d.domain FROM sl_group g JOIN sl_domain_entry d
            ON d.id=g.domain_entry_id WHERE g.group_id=sl_short_link.group_id) AS domain]]
        local rows,err=conn:query(sql,data.code,data.target_url,data.group_id,data.expires_at,tenant_id)
        if not rows then return nil,err end
        return rows[1], not rows[1] and "group or grant no longer available" or nil
    end)
end

--- 停用短链 / Disable a short link (set status=2)
-- @param code 短码
-- @return row or nil, err
function _M:disable(code, tenant_id)
    local sql = [[UPDATE sl_short_link l SET status=2, disabled_at=NOW()
        FROM sl_tenant t WHERE l.code=$1 AND l.status=1 AND t.id=$2
        AND t.status=1 AND t.deleted_at IS NULL AND l.group_id=ANY(t.group_ids) RETURNING l.*]]
    local res, err = self.db:query(sql, code, tenant_id)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 按分组查找 / Find links by group
-- @param group_id 分组 ID
-- @param limit 返回数量
-- @return rows or nil, err
function _M:find_by_group(group_id, limit)
    limit = limit or 100
    local sql = "SELECT * FROM sl_short_link WHERE group_id = $1 ORDER BY created_at DESC LIMIT $2"
    return self.db:query(sql, group_id, limit)
end

function _M:find_authorized(code,tenant_id)
    local rows,err=self.db:query([[SELECT l.* FROM sl_short_link l JOIN sl_tenant t
        ON l.group_id=ANY(t.group_ids) WHERE l.code=$1 AND t.id=$2 AND t.status=1
        AND t.deleted_at IS NULL]],code,tenant_id)
    return rows and rows[1],err
end
return _M
