-- lib/linklet/gateway/redirect.lua
-- 重定向处理器：HTTP 302 跳转
-- Redirect handler: HTTP 302 redirect

local setmetatable = setmetatable
local pcall = pcall

local _M = {}
_M.__index = _M

function _M.new()
    return setmetatable({}, _M)
end

--- HTTP 302 重定向 / HTTP 302 redirect
-- @param ctx 请求上下文
-- @param next 下一个处理函数（通常链末端，不调用）
function _M:handle(ctx, next)
    if not ctx.target_url then
        if ctx.response then
            ctx.response:not_found("target URL not resolved")
        end
        return nil, "no target URL"
    end

    -- 发送 302 重定向 / Send 302 redirect
    local ngx = ngx
    local ok = ngx ~= nil
    if ok then
        ngx.status = 302
        ngx.header["Location"] = ctx.target_url
        ngx.header["Content-Length"] = "0"
        return true
    end

    -- 非 OpenResty 环境（测试）/ Non-OpenResty (test)
    if ctx.response then
        ctx.response._status = 302
        ctx.response._location = ctx.target_url
    end
    return true
end

return _M
