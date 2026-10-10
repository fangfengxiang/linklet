-- src/models/domain_entry.lua
-- 域名入口模型：sl_domain_entry 数据访问
-- Domain entry model: sl_domain_entry data access

local setmetatable = setmetatable
local error = error

local BaseModel = require("models.base_model")
local _M = setmetatable({}, {__index = BaseModel})
_M.__index = _M

function _M.new(db)
    local self = BaseModel.new(db, "sl_domain_entry")
    return setmetatable(self, _M)
end

--- 创建域名入口 / Create a domain entry
-- 域名记录创建后不可修改（immutable）
-- @param tenant_id 租户 ID
-- @param domain 域名
-- @param label 标签（可选）
-- @param description 描述（可选）
-- @return row or nil, err
function _M:create(tenant_id, domain, label, description)
    if not tenant_id or not domain then
        return nil, "tenant_id and domain are required"
    end
    local sql = "INSERT INTO sl_domain_entry (tenant_id, domain, label, description, status, enabled_at) " ..
        "VALUES ($1, $2, $3, $4, 1, NOW()) RETURNING *"
    local res, err = self.db:query(sql, tenant_id, domain, label, description)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 按域名查找 / Find by domain string
-- @param domain 域名
-- @return row or nil
function _M:find_by_domain(domain)
    local sql = "SELECT * FROM sl_domain_entry WHERE domain = $1 AND status = 1 LIMIT 1"
    local res, err = self.db:query(sql, domain)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 按 ID 查找 / Find by ID
function _M:find_by_id(id)
    local sql = "SELECT * FROM sl_domain_entry WHERE id = $1 LIMIT 1"
    local res, err = self.db:query(sql, id)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 停用域名 / Disable a domain entry
-- 域名记录不可修改，但可以停用
-- @param id 域名入口 ID
-- @return row or nil, err
function _M:disable(id)
    local sql = "UPDATE sl_domain_entry SET status = 2, disabled_at = NOW(), updated_at = NOW() " ..
        "WHERE id = $1 AND status = 1 RETURNING *"
    local res, err = self.db:query(sql, id)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 按租户查找域名列表 / Find domains by tenant
-- @param tenant_id 租户 ID
-- @param limit 返回数量
-- @return rows or nil, err
function _M:find_by_tenant(tenant_id, limit)
    limit = limit or 100
    local sql = "SELECT * FROM sl_domain_entry WHERE tenant_id = $1 AND status != 3 " ..
        "ORDER BY created_at DESC LIMIT $2"
    return self.db:query(sql, tenant_id, limit)
end

return _M
