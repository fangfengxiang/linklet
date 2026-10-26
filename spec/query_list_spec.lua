local helper = require("helper")
local Core = require("linklet.core.short_link")
local CredentialHandler = require("linklet.admin.handlers.credential")
local TenantHandler = require("linklet.admin.handlers.tenant")
local Resources = require("linklet.admin.handlers.resources")
local ShortLinkHandler = require("linklet.admin.handlers.short_link")
local Credential = require("linklet.repository.credential")
local Response = require("linklet.http.response")
local json = require("cjson.safe")

local function context(params)
    return {tenant_id = 7, request = {all_params = function() return params or {} end},
        response = helper.mock_response()}
end

local function core(repository)
    local unused = function() error("unexpected write") end
    return Core.new({link_model = repository,
        short_link_repository = {create = unused, get = unused, update = unused, delete = unused}})
end

describe("Minimal management queries", function()
    it("makes platform group listing independent of tenant grants and keeps the optional filter", function()
        local observed = {}
        local handler = Resources.new({group_model = {
            find_all = function(_, limit) observed[#observed + 1] = {limit = limit}; return {{group_id = 1}} end,
            find_by_tenant = function(_, tenant_id, limit)
                observed[#observed + 1] = {tenant_id = tenant_id, limit = limit}
                return {{group_id = 2}}
            end,
        }})
        local ctx = context()
        handler:handle(ctx, "group", "list")
        assert.equals(1, ctx.response._body.data[1].group_id)
        ctx = context({tenant_id = "3"})
        handler:handle(ctx, "group", "list")
        assert.equals(2, ctx.response._body.data[1].group_id)
        assert.same({{limit = 100}, {tenant_id = 3, limit = 100}}, observed)
        ctx = context({tenant_id = false})
        handler:handle(ctx, "group", "list")
        assert.equals(400, ctx.response._status)
        assert.equals(2, #observed)
    end)

    it("returns only public credential fields even if an adapter accidentally supplies secrets", function()
        local handler = CredentialHandler.new({credential_model = {find_by_tenant = function(_, tenant_id, limit)
            assert.equals(9, tenant_id)
            assert.equals(100, limit)
            return {{id = 1, tenant_id = 9, access_key = "public-ak", status = 2,
                disabled_at = "2026-01-01", secret_key = "plaintext", secret_key_enc = "ciphertext"}}
        end}})
        local ctx = context({tenant_id = "9"})
        handler:list(ctx)
        local row = ctx.response._body.data[1]
        assert.equals(200, ctx.response._status)
        assert.equals("public-ak", row.access_key)
        assert.equals(2, row.status)
        assert.is_nil(row.secret_key)
        assert.is_nil(row.secret_key_enc)
        local encoded = assert(json.encode(ctx.response._body))
        assert.is_nil(encoded:find("plaintext", 1, true))
        assert.is_nil(encoded:find("ciphertext", 1, true))
    end)

    it("requires a valid tenant ID for credential listing and surfaces storage failures", function()
        local calls = 0
        local handler = CredentialHandler.new({credential_model = {find_by_tenant = function()
            calls = calls + 1
            return nil, "unavailable"
        end}})
        for _, params in ipairs({{}, {tenant_id = 0}, {tenant_id = false}, {tenant_id = "bad"},
            {tenant_id = 1.5}, {tenant_id = "9007199254740992"}}) do
            local ctx = context(params)
            handler:list(ctx)
            assert.equals(400, ctx.response._status)
        end
        assert.equals(0, calls)
        local ctx = context({tenant_id = 1})
        handler:list(ctx)
        assert.equals(500, ctx.response._status)
        assert.equals(1, calls)
    end)

    it("credential list reads never decrypt a secret", function()
        local repository = Credential.new(helper.mock_db({{id = 1, access_key = "ak", status = 1}}), {
            decrypt = function() error("list must not decrypt credentials") end,
        })
        assert.equals("ak", repository:find_by_tenant(1)[1].access_key)
        repository.db.query = function() return nil, "connection refused" end
        local rows, err = repository:find_by_tenant(1)
        assert.is_nil(rows)
        assert.equals("unavailable", err)
    end)

    it("passes the authenticated tenant and validated filter to one bounded authorized read", function()
        local calls = {}
        local use_case = core({find_all_authorized = function(_, tenant_id, group_id, limit)
            calls[#calls + 1] = {tenant_id = tenant_id, group_id = group_id, limit = limit}
            return {}
        end})
        assert.same({}, use_case:list(7))
        assert.same({}, use_case:list(7, "100"))
        assert.same({{tenant_id = 7, limit = 100}, {tenant_id = 7, group_id = 100, limit = 100}}, calls)
        for _, group_id in ipairs({false, 0, -1, 1.5, "bad", "4294967296", {}}) do
            local rows, err = use_case:list(7, group_id)
            assert.is_nil(rows)
            assert.equals("invalid_group_id", err.kind)
        end
        assert.equals(2, #calls)
    end)

    it("surfaces list storage failure through the Core and HTTP adapter", function()
        local handler = setmetatable({use_case = core({find_all_authorized = function()
            return nil, "unavailable"
        end})}, {__index = ShortLinkHandler})
        local ctx = context()
        handler:list(ctx)
        assert.equals(500, ctx.response._status)
        handler.use_case.link_model.find_all_authorized = function() return {{code = "visible"}} end
        handler:list(ctx)
        assert.equals(200, ctx.response._status)
        assert.equals("visible", ctx.response._body.data[1].code)
    end)

    it("serializes empty tenant grant sets as arrays when created, listed, or updated", function()
        local repository = {
            create = function() return {id = 1, name = "new", group_ids = {}} end,
            find_all = function() return {{id = 1, group_ids = {}}} end,
            grant = function() return {id = 1, group_ids = {}} end,
            set_status = function() return {id = 1, status = 2, group_ids = {}} end,
        }
        local tenant = TenantHandler.new({tenant_model = repository})
        local ctx = context({name = "new"})
        tenant:create(ctx)
        assert.is_not_nil(assert(json.encode(ctx.response._body)):find('"group_ids":[]', 1, true))
        tenant:list(ctx)
        assert.is_not_nil(assert(json.encode(ctx.response._body)):find('"group_ids":[]', 1, true))
        local resources = Resources.new({tenant_model = repository})
        for _, params in ipairs({{id = 1, group_ids = {}}, {id = 1, status = 2}}) do
            ctx = context(params)
            resources:handle(ctx, "tenant", params.status and "status" or "grant")
            assert.is_not_nil(assert(json.encode(ctx.response._body)):find('"group_ids":[]', 1, true))
        end
    end)

    it("serializes an empty list as an array in both JSON encoders", function()
        local response = Response.new()
        response:success_list({})
        assert.is_not_nil(assert(json.encode(response._body)):find('"data":[]', 1, true))
        assert.is_not_nil(Response._encode_json(response._body):find('"data":[]', 1, true))
        response:success_list({{id = 1}})
        assert.equals(1, response._body.data[1].id)
    end)
end)
