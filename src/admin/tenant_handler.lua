-- src/admin/tenant_handler.lua
-- 租户管理处理器：create, list
-- Tenant management handler: create, list
-- 路由: /api/v1/admin/tenant/*

local setmetatable = setmetatable
local tostring = tostring
local type = type

local _M = {}
_M.__index = _M

--- 创建租户管理处理器 / Create tenant handler
-- @param deps 依赖注入表
--   - tenant_model: 租户模型
function _M.new(deps)
    local self = setmetatable({}, _M)
    self.tenant_model = deps.tenant_model
    return self
end

--- 创建租户 / Create tenant
-- POST /api/v1/admin/tenant/create
-- @param ctx 请求上下文
-- @return true or nil, err
function _M:create(ctx)
    local params = ctx.params or ctx.request:all_params()
    local name = params.name

    if not name or name == "" then
        return ctx.response:error_response(4001, "name is required", 400)
    end

    local tenant, err = self.tenant_model:create(name)
    if not tenant then
        return ctx.response:internal_error("failed to create tenant: " .. tostring(err))
    end

    return ctx.response:success(tenant)
end

--- 查询租户列表 / List tenants
-- GET /api/v1/admin/tenant/list
-- @param ctx 请求上下文
-- @return true or nil, err
function _M:list(ctx)
    local params = (ctx.request and ctx.request:all_params()) or ctx.params or {}
    local limit = tonumber(params.limit) or 100

    local tenants, err = self.tenant_model:find_all(limit)
    if not tenants then
        return ctx.response:internal_error("failed to list tenants: " .. tostring(err))
    end

    return ctx.response:success(tenants)
end

return _M
