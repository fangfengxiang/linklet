-- src/models/tenant.lua
-- 租户模型：sl_tenant 数据访问
-- Tenant model: sl_tenant data access

local setmetatable = setmetatable

local BaseModel = require("models.base_model")
local _M = setmetatable({}, {__index = BaseModel})
_M.__index = _M

function _M.new(db)
    local self = BaseModel.new(db, "sl_tenant")
    return setmetatable(self, _M)
end

--- 创建租户 / Create a tenant
-- @param name 租户名称
-- @return row or nil, err
function _M:create(name)
    local sql = "INSERT INTO sl_tenant (name, status) VALUES ($1, 1) RETURNING *"
    local res, err = self.db:query(sql, name)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 按 ID 查找 / Find by ID
function _M:find_by_id(id)
    local sql = "SELECT * FROM sl_tenant WHERE id = $1 LIMIT 1"
    local res, err = self.db:query(sql, id)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 查询所有租户 / Find all tenants
-- @param limit 返回数量
-- @return rows or nil, err
function _M:find_all(limit)
    limit = limit or 100
    local sql = "SELECT * FROM sl_tenant ORDER BY created_at DESC LIMIT $1"
    return self.db:query(sql, limit)
end

return _M
