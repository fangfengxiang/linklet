-- SLDS port adapter. Linklet keeps its relational ownership and atomic writes.
local SLDS = require("slds")
local Policy = require("linklet.core.short_link_policy")
local _M = {}
_M.__index = _M

function _M.new(storage)
    return setmetatable({storage = assert(storage)}, _M)
end

local function actor(ctx)
    return type(ctx.actor) == "table" and ctx.actor.tenant_id
end

local function identity_allowed(identity)
    return identity.namespace == Policy.namespace
end

local function create_with_view(self, ctx, link)
    local validated = SLDS.ShortLink.new(link, Policy.lifecycle)
    if not validated or validated.status ~= SLDS.Lifecycle.ACTIVE or
        not Policy.valid_target(validated.target) then
        return nil, SLDS.Errors.INVALID
    end
    link = validated
    local group_id = link.metadata and link.metadata.group_id
    if not identity_allowed(link) or not actor(ctx) or type(group_id) ~= "number" or
        group_id < 1 or group_id > 4294967295 or group_id ~= math.floor(group_id) then
        return nil, SLDS.Errors.INVALID
    end
    for field in pairs(link.metadata) do
        if field ~= "group_id" then return nil, SLDS.Errors.INVALID end
    end
    local row, err = self.storage:create({
        code = link.code, target_url = link.target,
        group_id = link.metadata.group_id, expires_at = link.expires_at,
    }, actor(ctx))
    if not row then
        if err == "conflict" then return nil, SLDS.Errors.CONFLICT end
        if err == "group_unavailable" then return nil, SLDS.Errors.INVALID end
        return nil, err or "unavailable"
    end
    local created, conversion_err = self.storage:to_entity(row)
    if not created then return nil, conversion_err end
    return created, nil, {domain = row.domain}
end

function _M:create(ctx, link)
    local created, err = create_with_view(self, ctx, link)
    return created, err
end

-- Linklet's creation operation also needs the transaction-confirmed domain.
-- This view stays outside the SLDS entity and persistent metadata.
function _M:create_with_view(ctx, link)
    return create_with_view(self, ctx, link)
end

function _M:get(ctx, identity)
    if not identity_allowed(identity) then return nil, SLDS.Errors.NOT_FOUND end
    local row, err = self.storage:find_by_code(identity.code)
    if not row then return nil, err or SLDS.Errors.NOT_FOUND end
    return self.storage:to_entity(row)
end

function _M:update(ctx, identity, patch)
    if patch.namespace ~= nil or patch.code ~= nil then error("identity is immutable", 2) end
    if not identity_allowed(identity) then return nil, SLDS.Errors.NOT_FOUND end
    if not actor(ctx) or not Policy.valid_disable(patch) then return nil, SLDS.Errors.INVALID end
    -- The SQL predicate checks current grants and ACTIVE state in the same write.
    -- No stale pre-read can overwrite fields, change ownership or revive a link.
    local row, err = self.storage:disable(identity.code, actor(ctx))
    if not row then return nil, err or SLDS.Errors.NOT_FOUND end
    return self.storage:to_entity(row)
end

function _M:delete(ctx, identity)
    -- Linklet exposes terminal disable only. Codes remain permanently reserved.
    return nil, SLDS.Errors.INVALID
end
return _M
