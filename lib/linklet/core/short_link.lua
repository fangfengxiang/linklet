-- Domain use case: injected dependencies, domain errors, no transport concerns.
local Time = require("linklet.core.time")
local SLDS = require("slds")
local Policy = require("linklet.core.short_link_policy")
local _M = {}
_M.__index = _M

function _M.new(deps)
    assert(deps.short_link_repository, "short_link_repository is required")
    local generator = deps.code_generator or {generate = function()
        local id, err = deps.id_generator:next_id()
        if not id then return nil, err or "unavailable" end
        return deps.obfuscator.generate(id)
    end}
    deps.code_generator = generator
    deps.interactor = SLDS.new({
        repository = deps.short_link_repository, code_generator = generator,
        lifecycle = Policy.lifecycle, clock = deps.now or os.time,
    })
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
    if not Policy.valid_target(url) then
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

    -- Scope the result view to this call. Concurrent creates never share result
    -- state, and ctx remains read-only. SLDS still owns generic orchestration.
    local view
    local repository = setmetatable({create = function(_, ctx, candidate)
        local created, write_err, committed = self.short_link_repository:create_with_view(ctx, candidate)
        view = committed
        return created, write_err
    end}, {__index = self.short_link_repository})
    local operation = SLDS.new({repository = repository, code_generator = self.code_generator,
        lifecycle = Policy.lifecycle, clock = self.now or os.time})
    local link, create_err = operation:create({actor = {tenant_id = tenant_id}}, {
        namespace = Policy.namespace, target = url, expires_at = params.expires_at and Time.parse(params.expires_at),
        metadata = {group_id = group_id},
    })
    if not link then
        if create_err == SLDS.Errors.CONFLICT or create_err == SLDS.Errors.INVALID then
            return failure("creation conflicted with current state", "conflict")
        end
        return failure("failed to create link", "unavailable")
    end
    return {code = link.code, domain = view.domain}
end

function _M:disable(tenant_id, code)
    if type(code) ~= "string" or code == "" or #code > 20 then
        return failure("code is required", "invalid_code")
    end
    local link, err = self.interactor:update({actor = {tenant_id = tenant_id}},
        SLDS.Identity.new(Policy.namespace, code), {status = SLDS.Lifecycle.DISABLED})
    if not link then
        if err == SLDS.Errors.NOT_FOUND or err == SLDS.Errors.INVALID then
            return failure("link not found or already disabled", "link_missing")
        end
        return failure("database unavailable", "unavailable")
    end
    return {code = link.code, status = "disabled"}
end

function _M:get(tenant_id, code)
    if type(code) ~= "string" or code == "" or #code > 20 then
        return failure("code is required", "invalid_code")
    end
    local row, err = self.link_model:find_authorized(code, tenant_id)
    if err then return failure("database unavailable", "unavailable") end
    if not row then return failure("link not found", "not_found") end
    return row
end
function _M:list(tenant_id, group_id)
    if group_id ~= nil then
        local kind = type(group_id)
        group_id = (kind == "number" or kind == "string") and tonumber(group_id) or nil
        if not group_id or group_id < 1 or group_id > 4294967295 or group_id ~= math.floor(group_id) then
            return failure("group_id must be a uint32", "invalid_group_id")
        end
    end
    local rows, err = self.link_model:find_all_authorized(tenant_id, group_id, 100)
    if not rows or err then return failure("database unavailable", "unavailable") end
    return rows
end
return _M
