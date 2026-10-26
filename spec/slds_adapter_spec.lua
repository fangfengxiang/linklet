local SLDS = require("slds")
local Adapter = require("linklet.repository.slds")
local Storage = require("linklet.repository.short_link")
local Policy = require("linklet.core.short_link_policy")

describe("Linklet SLDS integration contract", function()
    local storage, adapter, ctx, row, calls
    before_each(function()
        calls = 0
        ctx = {actor = {tenant_id = 7}, request_id = "request-1"}
        row = {code = "code01", target_url = "https://example.com", group_id = 100,
            status = 1, expires_epoch = 200.5}
        storage = {
            create = function(_, data, tenant)
                calls = calls + 1
                assert.equals(7, tenant)
                assert.equals(100, data.group_id)
                assert.equals(200.5, data.expires_at)
                assert.is_nil(data.tenant_id)
                return row
            end,
            to_entity = Storage.to_entity,
            find_by_code = function() calls = calls + 1; return row end,
            disable = function(_, code, tenant)
                calls = calls + 1
                assert.equals("code01", code)
                assert.equals(7, tenant)
                return {code = code, target_url = row.target_url, group_id = 100, status = 2}
            end,
        }
        adapter = Adapter.new(storage)
    end)

    local function entity(metadata, namespace)
        return assert(SLDS.ShortLink.new({namespace = namespace or Policy.namespace, code = "code01",
            target = "https://example.com", expires_at = 200.5, metadata = metadata or {group_id = 100}}))
    end

    it("maps persistent group metadata and opaque actor context through Interactor", function()
        local api = SLDS.new({repository = adapter, lifecycle = Policy.lifecycle})
        local link = assert(api:create(ctx, {namespace = Policy.namespace, code = "code01",
            target = row.target_url, expires_at = 200.5, metadata = {group_id = 100}}))
        assert.equals(100, link.metadata.group_id)
        assert.same({actor = {tenant_id = 7}, request_id = "request-1"}, ctx)
        assert.equals(1, calls)
    end)

    it("declares the relational metadata subset instead of silently dropping fields", function()
        for _, metadata in ipairs({{}, {group_id = 0}, {group_id = 1.5}, {group_id = "100"},
            {group_id = 100, business = {order_id = 1}}}) do
            local result, err = adapter:create(ctx, entity(metadata))
            assert.is_nil(result)
            assert.equals(SLDS.Errors.INVALID, err)
        end
        assert.equals(0, calls)
        assert.is_nil(adapter:create({}, entity()))
        assert.is_nil(adapter:create(ctx, entity(nil, "another-namespace")))
    end)

    it("distinguishes duplicate creation, revoked state, and infrastructure failure", function()
        for _, pair in ipairs({{"conflict", SLDS.Errors.CONFLICT},
            {"group_unavailable", SLDS.Errors.INVALID}, {"unavailable", "unavailable"}}) do
            storage.create = function() return nil, pair[1] end
            local result, err = adapter:create(ctx, entity())
            assert.is_nil(result)
            assert.equals(pair[2], err)
        end
    end)

    it("rejects invalid creation states and host URL policy before any write", function()
        for _, status in ipairs({SLDS.Lifecycle.DELETED, SLDS.Lifecycle.DISABLED}) do
            local candidate = entity()
            candidate.status = status
            local value, err = adapter:create(ctx, candidate)
            assert.is_nil(value)
            assert.equals(SLDS.Errors.INVALID, err)
        end
        local candidate = entity()
        candidate.target = "ftp://example.com"
        assert.equals(SLDS.Errors.INVALID, select(2, adapter:create(ctx, candidate)))
        assert.equals(0, calls)
    end)

    it("allows only terminal disable and leaves atomic current authorization to storage", function()
        local api = SLDS.new({repository = adapter, lifecycle = Policy.lifecycle})
        local identity = SLDS.Identity.new(Policy.namespace, "code01")
        assert.equals(SLDS.Lifecycle.DISABLED, assert(api:update(ctx, identity,
            {status = SLDS.Lifecycle.DISABLED})).status)
        for _, patch in ipairs({{status = SLDS.Lifecycle.ACTIVE}, {target = "https://changed.example"},
            {expires_at = 999}, {metadata = {group_id = 2}},
            {status = SLDS.Lifecycle.DISABLED, target = row.target_url}}) do
            local value, err = api:update(ctx, identity, patch)
            assert.is_nil(value)
            assert.equals(SLDS.Errors.INVALID, err)
        end
        assert.equals(1, calls)
        assert.has_error(function() api:update(ctx, identity, {code = "changed"}) end)
        assert.has_error(function() adapter:update(ctx, identity, {namespace = "changed"}) end)
        assert.equals(SLDS.Errors.INVALID, select(2, adapter:delete(ctx, identity)))
    end)

    it("preserves missing and failed reads and writes without a pre-read", function()
        local identity = SLDS.Identity.new(Policy.namespace, "code01")
        storage.find_by_code = function() error("disable must not read first") end
        storage.disable = function() return nil end
        assert.equals(SLDS.Errors.NOT_FOUND, select(2,
            adapter:update(ctx, identity, {status = SLDS.Lifecycle.DISABLED})))
        storage.disable = function() return nil, "unavailable" end
        assert.equals("unavailable", select(2,
            adapter:update(ctx, identity, {status = SLDS.Lifecycle.DISABLED})))
        assert.equals(SLDS.Errors.INVALID, select(2,
            adapter:update({}, identity, {status = SLDS.Lifecycle.DISABLED})))
        storage.find_by_code = function() return nil end
        assert.equals(SLDS.Errors.NOT_FOUND, select(2, adapter:get(ctx, identity)))
        storage.find_by_code = function() return nil, "unavailable" end
        assert.equals("unavailable", select(2, adapter:get(ctx, identity)))
        assert.equals(SLDS.Errors.NOT_FOUND, select(2,
            adapter:get(ctx, SLDS.Identity.new("other", "code01"))))
    end)

    it("normalizes storage values before pure resolution and keeps metadata snapshots isolated", function()
        local store = Storage.new({query = function()
            return {{code = "code01", target_url = row.target_url, group_id = "100", status = "1",
                expires_epoch = "200.5", domain = "S.Example.com", domain_status = "2"}}
        end})
        local view = assert(store:find_for_resolution("code01"))
        assert.equals("s.example.com", view.domain)
        assert.equals(2, view.domain_status)
        assert.is_false(view.domain_deleted)
        local identity = SLDS.Identity.new(Policy.namespace, "code01")
        local decision = SLDS.Resolution.resolve(view.link, identity, 200, Policy.lifecycle)
        assert.is_true(decision.resolvable)
        assert.equals(200.5, decision.expires_at)
        local metadata = view.link:to_table().metadata
        metadata.group_id = 999
        assert.equals(100, view.link.metadata.group_id)
        assert.is_false(SLDS.Resolution.resolve(view.link, identity, 200.5, Policy.lifecycle).resolvable)
        assert.is_nil(store:to_entity({status = 9}))
    end)
end)
