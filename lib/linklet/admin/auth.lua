-- lib/linklet/admin/auth.lua
-- AK/SK 认证中间件
-- AK/SK HMAC authentication middleware

local setmetatable = setmetatable

local Crypto = require("linklet.crypto")
local _M = {}
_M.__index = _M

function _M.new(credential_model, verify_signature)
    assert(credential_model and type(credential_model.find_by_access_key)=="function",
        "credential repository is required")
    local self = setmetatable({}, _M)
    self.credential_model = credential_model
    self.verify_signature = verify_signature or Crypto.verify_signature
    return self
end

--- 认证中间件 / Authentication middleware
-- 从请求头提取 AK 和签名，验证 HMAC 签名
-- 验证通过后将 tenant_id 存入 ctx
-- @param ctx 请求上下文
-- @param next 下一个处理函数
function _M:handle(ctx, next)
    local req = ctx.request
    if not req then
        return nil, "no request context"
    end

    -- 从请求头获取凭证 / Get credentials from headers
    local access_key = req:header("X-Access-Key") or req:header("X-AK")
    local signature = req:header("X-Signature") or req:header("X-Sign")
    local timestamp = req:header("X-Timestamp")

    if type(access_key) ~= "string" or access_key == "" then
        ctx.auth_error = "missing access key"
        if ctx.response then
            ctx.response:unauthorized(ctx.auth_error)
        end
        return nil, ctx.auth_error
    end
    if type(signature) ~= "string" or signature == "" then
        ctx.auth_error = "missing signature"
        if ctx.response then
            ctx.response:unauthorized(ctx.auth_error)
        end
        return nil, ctx.auth_error
    end

    -- 时间戳校验（防止重放攻击）/ Timestamp validation
    if type(timestamp) ~= "string" then
        ctx.auth_error = "missing timestamp"
        if ctx.response then ctx.response:unauthorized(ctx.auth_error) end
        return nil, ctx.auth_error
    end
    if timestamp then
        local ts = tonumber(timestamp)
        if not ts or ts ~= math.floor(ts) then
            ctx.auth_error = "invalid timestamp"
            return nil, ctx.auth_error
        end
        -- OpenResty 环境使用 ngx.time
        local now
        local ngx = ngx
        local ok = ngx ~= nil
        if ok and ngx.time then
            now = ngx.time()
        else
            now = os.time()
        end
        local diff = math.abs(now - ts)
        if diff > 300 then  -- 5 分钟窗口 / 5-minute window
            ctx.auth_error = "request expired"
            if ctx.response then
                ctx.response:unauthorized(ctx.auth_error)
            end
            return nil, ctx.auth_error
        end
    end

    -- 查找凭证 / Look up credential
    local cred, cerr = self.credential_model:find_by_access_key(access_key)
    if cerr then
        if ctx.response then ctx.response:internal_error("credential storage unavailable") end
        return nil, "credential storage unavailable"
    end
    if not cred then
        ctx.auth_error = "invalid access key"
        if ctx.response then
            ctx.response:unauthorized(ctx.auth_error)
        end
        return nil, ctx.auth_error
    end

    -- 构造待签名字符串 / Build string to sign
    local method = req:method()
    local uri = req.signature_uri and req:signature_uri() or req:uri()
    -- 读取原始请求体用于签名验证 / Read raw body for signature
    local body = ""
    if req.raw_body then
        local err
        body, err = req:raw_body()
        if not body then
            if ctx.response then ctx.response:error_response(4000, "cannot read request body", 400) end
            return nil, err
        end
    elseif ctx.raw_body then
        body = ctx.raw_body
    end
    local string_to_sign = method .. "\n" .. uri .. "\n" .. (timestamp or "") .. "\n" .. body

    -- 验证签名 / Verify signature
    local valid = self.verify_signature(cred.secret_key, string_to_sign, signature)
    if not valid then
        ctx.auth_error = "invalid signature"
        if ctx.response then
            ctx.response:unauthorized(ctx.auth_error)
        end
        return nil, ctx.auth_error
    end

    -- 认证通过，设置租户身份 / Auth passed, set tenant identity
    ctx.tenant_id = cred.tenant_id
    ctx.access_key = access_key

    return next()
end

return _M
