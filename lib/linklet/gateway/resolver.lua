-- Cache-first resolution over a normalized storage projection.
local slds = require("slds")
local Host = require("linklet.gateway.host")
local _M = {}
_M.__index = _M

local function failure(kind, message)
    return nil, {kind = kind, message = message}
end

function _M.new(deps)
    local ttl = deps.cache_ttl or 300
    assert(type(ttl) == "number" and ttl > 0 and ttl < math.huge, "cache_ttl must be positive and finite")
    return setmetatable({
        repository = assert(deps.resolution_repository, "resolution_repository is required"),
        cache = deps.cache,
        cache_ttl = ttl,
        now = deps.now or os.time,
        lifecycle = deps.lifecycle,
    }, _M)
end

function _M:resolve(host, code)
    if type(code) ~= "string" or code == "" then return failure("not_found", "missing code") end
    local normalized = Host.normalize(host)
    if not normalized then return failure("not_found", "invalid host") end
    local key = Host.key(normalized, code)
    local cached = self.cache and self.cache:get(key)
    if cached then return {target_url = cached, cache_hit = true} end

    local generation = self.cache and self.cache:generation()
    local snapshot, err = self.repository:find_for_resolution(code)
    if not snapshot then
        if err then return failure("unavailable", "database unavailable") end
        return failure("not_found", "short link not found")
    end
    if normalized ~= Host.normalize(snapshot.domain) then
        return failure("not_found", "host does not match group domain")
    end
    if snapshot.domain_status ~= 2 or snapshot.domain_deleted then
        return failure("gone", "domain unavailable")
    end

    local now = self.now()
    local identity = slds.Identity.new(snapshot.link.namespace, code)
    local decision = slds.Resolution.resolve(snapshot.link, identity, now, self.lifecycle)
    if not decision.resolvable then
        return failure("gone", decision.status == slds.Resolution.EXPIRED and "link expired" or "link disabled")
    end
    local ttl = self.cache_ttl
    if decision.expires_at then ttl = math.min(ttl, decision.expires_at - now) end
    if self.cache then
        self.cache:set_for_generation(key, decision.target, ttl, generation)
    end
    return {target_url = decision.target, expires_at = decision.expires_at,
        metadata = snapshot.link:to_table().metadata}
end
return _M
