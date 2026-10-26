-- lib/linklet/repository/short_link.lua
-- 短链模型：sl_short_link 数据访问
-- Link model: sl_short_link data access

local setmetatable = setmetatable
local tostring = tostring

local Base = require("linklet.repository.base")
local SLDS = require("slds")
local Policy = require("linklet.core.short_link_policy")
local Errors = require("linklet.repository.errors")
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
        return nil, Errors.normalize(err)
    end
    return res[1]
end

--- 创建短链 / Create a short link
-- @param data {code, target_url, group_id, expires_at?} (expiration is epoch seconds)
-- @return row or nil, err
function _M:create(data, tenant_id)
    if not data.code or not data.target_url or not data.group_id then return nil,"missing required fields" end
    local row, failure = self.db:transaction(function(conn)
        -- Use a fresh snapshot after waiting for a concurrent rebind.
        local locked, lock_err = conn:query("SELECT group_id FROM sl_group WHERE group_id=$1 FOR UPDATE",data.group_id)
        if not locked then return nil, lock_err end
        local sql = [[INSERT INTO sl_short_link(code,target_url,group_id,status,expires_at)
            SELECT $1,$2,s.group_id,1,to_timestamp($4::double precision) FROM sl_group s
            JOIN sl_domain_entry d ON d.id=s.domain_entry_id
            WHERE s.group_id=$3 AND s.status=1 AND s.deleted_at IS NULL AND d.status=2
            AND d.deleted_at IS NULL AND ($5::bigint IS NULL OR EXISTS(SELECT 1 FROM sl_tenant t
            WHERE t.id=$5 AND t.status=1 AND t.deleted_at IS NULL AND s.group_id=ANY(t.group_ids)))
            RETURNING *, EXTRACT(EPOCH FROM expires_at) AS expires_epoch,
            (SELECT d.domain FROM sl_group g JOIN sl_domain_entry d
            ON d.id=g.domain_entry_id WHERE g.group_id=sl_short_link.group_id) AS domain]]
        local rows,err=conn:query(sql,data.code,data.target_url,data.group_id,data.expires_at,tenant_id)
        if not rows then return nil,err end
        return rows[1], not rows[1] and "group_unavailable" or nil
    end)
    return row, failure and Errors.normalize(failure) or nil
end

--- 停用短链 / Disable a short link (set status=2)
-- @param code 短码
-- @return row or nil, err
function _M:disable(code, tenant_id)
    local sql = [[UPDATE sl_short_link l SET status=2, disabled_at=NOW()
        FROM sl_tenant t WHERE l.code=$1 AND l.status=1 AND t.id=$2
        AND t.status=1 AND t.deleted_at IS NULL AND l.group_id=ANY(t.group_ids)
        RETURNING l.*, EXTRACT(EPOCH FROM l.expires_at) AS expires_epoch]]
    local res, err = self.db:query(sql, code, tenant_id)
    if not res then
        return nil, Errors.normalize(err)
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

-- Authorization is part of the read statement, including after authentication.
function _M:find_all_authorized(tenant_id, group_id, limit)
    local rows, err = self.db:query([[SELECT l.id,l.code,l.target_url,l.group_id,l.status,
        l.expires_at,l.created_at,l.disabled_at,d.domain
        FROM sl_short_link l JOIN sl_tenant t ON l.group_id=ANY(t.group_ids)
        JOIN sl_group g ON g.group_id=l.group_id
        JOIN sl_domain_entry d ON d.id=g.domain_entry_id
        WHERE t.id=$1 AND t.status=1 AND t.deleted_at IS NULL
        AND ($2::bigint IS NULL OR l.group_id=$2)
        ORDER BY l.created_at DESC,l.id DESC LIMIT $3]], tenant_id, group_id, limit or 100)
    return rows, Errors.normalize(err)
end

function _M:to_entity(row)
    local status = tonumber(row.status)
    if status ~= 1 and status ~= 2 then return nil, "unavailable" end
    return SLDS.ShortLink.new({
        namespace = Policy.namespace, code = row.code, target = row.target_url,
        status = status == 1 and SLDS.Lifecycle.ACTIVE or SLDS.Lifecycle.DISABLED,
        expires_at = tonumber(row.expires_epoch), metadata = {group_id = tonumber(row.group_id)},
    }, Policy.lifecycle)
end

function _M:find_for_resolution(code)
    local row, err = self:find_by_code(code)
    if not row then return nil, err end
    local link, conversion_err = self:to_entity(row)
    if not link then return nil, conversion_err end
    local deleted = row.domain_deleted_at
    return {
        link = link,
        domain = require("linklet.core.domain_entry").normalize(row.domain),
        domain_status = tonumber(row.domain_status),
        domain_deleted = deleted ~= nil and not (ngx and deleted == ngx.null),
    }
end
return _M
