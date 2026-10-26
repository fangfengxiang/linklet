-- Gateway transport adapter: the resolver returns data and never sends HTTP.
local _M = {}
_M.__index = _M

function _M.new(resolver)
    return setmetatable({resolver = resolver}, _M)
end

function _M:handle(ctx)
    local code = ctx.uri and ctx.uri:match("^/([a-zA-Z0-9]+)$")
    if ctx.method ~= "GET" or not code then
        return ctx.response:not_found("route not found")
    end
    local result, err = self.resolver:resolve(ctx.host, code)
    if not result then
        if err.kind == "not_found" then return ctx.response:not_found(err.message) end
        if err.kind == "gone" then return ctx.response:gone(err.message) end
        return ctx.response:internal_error(err.message)
    end
    ctx.response.sent = true
    if ngx then
        ngx.status = 302
        ngx.header["Location"] = result.target_url
        ngx.header["Content-Length"] = "0"
    else
        ctx.response._status = 302
        ctx.response._location = result.target_url
    end
    return true
end
return _M
