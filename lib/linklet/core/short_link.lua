-- Domain use case: injected dependencies, domain errors, no transport concerns.
local Time = require("linklet.core.time")
local _M = {}
_M.__index = _M

function _M.new(deps)
    return setmetatable(deps, _M)
end

local function failure(message, kind)
    return nil, {message = message, kind = kind}
end

function _M:create(tenant_id, params)
    local url, group_id = params.target_url, tonumber(params.group_id)
    if type(url) ~= "string" or url == "" then
        return failure("target_url is required", "invalid_url")
    end
    if #url > 2048 or not url:match("^https?://[^/%s?#]+") or url:find("[%c%s]") then
        return failure("target_url must be an HTTP(S) URL", "invalid_url")
    end
    if not group_id or group_id < 1 or group_id > 4294967295 or group_id ~= math.floor(group_id) then
        return failure("group_id must be a uint32", "invalid_group_id")
    end
    if params.expires_at ~= nil then
        local epoch = Time.parse(params.expires_at)
        if not epoch or epoch <= (self.now or os.time)() then
            return failure("expires_at must be a future RFC3339 timestamp", "invalid_expiry")
        end
    end

    local group, err = self.group_model:find_by_id_with_domain(group_id)
    if err then return failure("database unavailable", "unavailable") end
    if not group or tonumber(group.status) ~= 1 then
        return failure("group not found or inactive", "group_inactive")
    end
    local allowed, grant_err = self.tenant_model:authorized(tenant_id, group_id)
    if grant_err then return failure("database unavailable", "unavailable") end
    if not allowed then return failure("group not authorized", "group_forbidden") end
    if not group.domain or group.domain == "" or tonumber(group.domain_status) ~= 2 then
        return failure("domain not configured for group", "domain_unavailable")
    end

    local id = self.id_generator:next_id()
    if not id then return failure("failed to generate ID", "unavailable") end
    local code = self.obfuscator.generate(id)
    local link = self.link_model:create({
        code = code, target_url = url, group_id = group_id, expires_at = params.expires_at,
    }, tenant_id)
    if not link then return failure("failed to create link", "unavailable") end
    return {code = code, domain = link.domain}
end
return _M
