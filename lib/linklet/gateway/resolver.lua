local _M = {}
_M.__index = _M
function _M.new(deps)
    local ttl=deps.cache_ttl or 300
    assert(type(ttl)=="number" and ttl>0 and ttl<math.huge,"cache_ttl must be positive and finite")
    return setmetatable({link_model=deps.link_model,cache=deps.cache,cache_ttl=ttl},_M)
end
function _M:handle(ctx, next)
    if ctx.resolved then return next() end
    local code = ctx.params and ctx.params.code
    if not code then
        ctx.response:not_found("missing code")
        return nil, "missing code"
    end
    local generation = self.cache and self.cache:generation()
    local link, err = self.link_model:find_by_code(code)
    if not link then
        if err then ctx.response:internal_error("database unavailable")
        else ctx.response:not_found("short link not found") end
        return nil, err or "not found"
    end
    local host = require("linklet.gateway.host")
    if host.normalize(ctx.host)~=host.normalize(link.domain) or not host.normalize(ctx.host) then
        ctx.response:not_found("host does not match scene domain")
        return nil,"host mismatch"
    end
    if tonumber(link.status)~=1 or tonumber(link.domain_status)~=2 or
        (link.domain_deleted_at and link.domain_deleted_at~=(ngx and ngx.null)) then
        ctx.response:gone("link disabled")
        return nil,"disabled"
    end
    local now = ngx and ngx.now() or os.time()
    -- PostgreSQL converts TIMESTAMPTZ to epoch, avoiding HTTP-date parsing and time zones.
    local expires = tonumber(link.expires_epoch) or tonumber(link.expires_at)
    if expires and expires <= now then
        ctx.response:gone("link expired")
        return nil, "expired"
    end
    local ttl = self.cache_ttl
    if expires then ttl = math.min(ttl, expires - now) end
    ctx.target_url = link.target_url
    ctx.resolved = true
    if self.cache and generation == self.cache:generation() then
        self.cache:set(host.key(ctx.host,code), link.target_url, ttl)
    end
    return next()
end
return _M
