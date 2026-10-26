-- lib/linklet/admin/handlers/credential.lua
-- 凭证管理处理器：create, disable
-- Credential management handler: create, disable
-- 路由: /api/v1/admin/credential/*

local setmetatable = setmetatable
local tostring = tostring
local type = type

local _M = {}
_M.__index = _M

--- 创建凭证管理处理器 / Create credential handler
-- @param deps 依赖注入表
--   - credential_model: 凭证模型
--   - tenant_model: 租户模型（校验租户存在）
function _M.new(deps)
    local self = setmetatable({}, _M)
    self.credential_model = deps.credential_model
    self.tenant_model = deps.tenant_model
    self.crypto = deps.crypto or require("linklet.crypto")
    return self
end

--- 创建凭证 / Create credential
-- POST /api/v1/admin/credential/create
-- @param ctx 请求上下文
-- @return true or nil, err
function _M:create(ctx)
    local params = ctx.params or ctx.request:all_params()
    local tenant_id = tonumber(params.tenant_id)

    if not tenant_id or tenant_id<1 or tenant_id>9007199254740991 or tenant_id~=math.floor(tenant_id) then
        return ctx.response:error_response(4001, "tenant_id is required", 400)
    end

    -- 校验租户存在 / Validate tenant exists
    local tenant,terr = self.tenant_model:find_by_id(tenant_id)
    if terr then return ctx.response:internal_error("database unavailable") end
    if not tenant then
        return ctx.response:error_response(4002, "tenant not found", 404)
    end

    -- 生成 AK/SK / Generate AK/SK
    local access_key = params.access_key or self.crypto.random_key()
    local secret_key = params.secret_key or self.crypto.random_key()

    if type(access_key) ~= "string" or access_key == "" or #access_key > 128 or
        type(secret_key) ~= "string" or #secret_key < 16 or #secret_key > 256 then
        return ctx.response:error_response(4001, "invalid access key or secret key", 400)
    end

    local cred, err = self.credential_model:create(tenant_id, access_key, secret_key)
    if not cred then
        return ctx.response:internal_error("failed to create credential")
    end

    -- 返回时附带明文 SK（仅创建时展示一次）/ Return plaintext SK (shown once)
    cred.secret_key = secret_key

    return ctx.response:success(cred)
end

--- 禁用凭证 / Disable credential
-- PUT /api/v1/admin/credential/disable
-- @param ctx 请求上下文
-- @return true or nil, err
function _M:disable(ctx)
    local params = ctx.params or ctx.request:all_params()
    local access_key = params.access_key

    if type(access_key)~="string" or access_key=="" or #access_key>128 then
        return ctx.response:error_response(4001, "access_key is required", 400)
    end

    local result, err = self.credential_model:disable(access_key)
    if err then return ctx.response:internal_error("database unavailable") end
    if not result then
        return ctx.response:error_response(4003, "credential not found or already disabled", 404)
    end

    return ctx.response:success({access_key = access_key, status = "disabled"})
end

-- Internal operator view. Whitelist again at the transport boundary.
function _M:list(ctx)
    local params = ctx.request:all_params()
    local raw = params.tenant_id
    local tenant_id = (type(raw) == "number" or type(raw) == "string") and tonumber(raw) or nil
    if not tenant_id or tenant_id < 1 or tenant_id > 9007199254740991 or tenant_id ~= math.floor(tenant_id) then
        return ctx.response:error_response(4001, "tenant_id is required", 400)
    end
    local rows, err = self.credential_model:find_by_tenant(tenant_id, 100)
    if not rows or err then return ctx.response:internal_error("database unavailable") end
    local safe = {}
    local fields = {"id", "tenant_id", "access_key", "status", "description", "created_at", "updated_at", "disabled_at"}
    for index, row in ipairs(rows) do
        local item = {}
        for _, field in ipairs(fields) do item[field] = row[field] end
        safe[index] = item
    end
    return ctx.response:success_list(safe)
end
return _M
