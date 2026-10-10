-- spec/admin_handler_spec.lua
-- Admin 管理处理器测试 / Admin handler tests

local helper = require("helper")
local TenantHandler = require("admin.tenant_handler")
local CredentialHandler = require("admin.credential_handler")

describe("Admin Handlers", function()
    describe("TenantHandler", function()
        local handler, mock_tenant_model, resp

        before_each(function()
            mock_tenant_model = {
                create = function(self, name)
                    return {id = 1, name = name, status = 1}
                end,
                find_all = function(self, limit)
                    return {{id = 1, name = "tenant-1", status = 1}}
                end,
                find_by_id = function(self, id)
                    if id == 1 then
                        return {id = 1, name = "tenant-1", status = 1}
                    end
                    return nil
                end,
            }
            handler = TenantHandler.new({tenant_model = mock_tenant_model})
            resp = helper.mock_response()
        end)

        describe("create", function()
            it("creates a tenant with valid name", function()
                local ctx = {
                    params = {name = "acme-corp"},
                    response = resp,
                }
                handler:create(ctx)
                assert.equals(200, resp._status)
                assert.equals(0, resp._body.code)
                assert.equals("acme-corp", resp._body.data.name)
            end)

            it("returns 400 when name is missing", function()
                local ctx = {
                    params = {},
                    response = resp,
                }
                handler:create(ctx)
                assert.equals(400, resp._status)
                assert.equals(4001, resp._body.code)
            end)

            it("returns 500 on database error", function()
                mock_tenant_model.create = function() return nil, "db error" end
                local ctx = {
                    params = {name = "test"},
                    response = resp,
                }
                handler:create(ctx)
                assert.equals(500, resp._status)
            end)
        end)

        describe("list", function()
            it("lists tenants", function()
                local ctx = {
                    request = {all_params = function() return {} end},
                    response = resp,
                }
                handler:list(ctx)
                assert.equals(200, resp._status)
                assert.truthy(resp._body.data)
                assert.equals(1, #resp._body.data)
            end)

            it("passes limit param", function()
                local captured_limit
                mock_tenant_model.find_all = function(self, limit)
                    captured_limit = limit
                    return {}
                end
                local ctx = {
                    params = {limit = "50"},
                    response = resp,
                }
                handler:list(ctx)
                assert.equals(50, captured_limit)
            end)
        end)
    end)

    describe("CredentialHandler", function()
        local handler, mock_credential_model, mock_tenant_model, resp

        before_each(function()
            mock_tenant_model = {
                find_by_id = function(self, id)
                    if id == 1 then
                        return {id = 1, name = "tenant-1"}
                    end
                    return nil
                end,
            }
            mock_credential_model = {
                create = function(self, tenant_id, ak, sk)
                    return {id = 1, tenant_id = tenant_id, access_key = ak, status = 1}
                end,
                disable = function(self, ak)
                    if ak == "existing-ak" then
                        return {id = 1}
                    end
                    return nil
                end,
            }
            handler = CredentialHandler.new({
                credential_model = mock_credential_model,
                tenant_model = mock_tenant_model,
            })
            resp = helper.mock_response()
        end)

        describe("create", function()
            it("creates a credential with valid tenant_id", function()
                local ctx = {
                    params = {tenant_id = 1},
                    response = resp,
                }
                handler:create(ctx)
                assert.equals(200, resp._status)
                assert.truthy(resp._body.data.access_key)
                assert.truthy(resp._body.data.secret_key)
            end)

            it("returns 400 when tenant_id is missing", function()
                local ctx = {
                    params = {},
                    response = resp,
                }
                handler:create(ctx)
                assert.equals(400, resp._status)
                assert.equals(4001, resp._body.code)
            end)

            it("returns 404 when tenant not found", function()
                local ctx = {
                    params = {tenant_id = 999},
                    response = resp,
                }
                handler:create(ctx)
                assert.equals(404, resp._status)
                assert.equals(4002, resp._body.code)
            end)

            it("accepts custom access_key and secret_key", function()
                local ctx = {
                    params = {tenant_id = 1, access_key = "custom-ak", secret_key = "custom-sk"},
                    response = resp,
                }
                handler:create(ctx)
                assert.equals(200, resp._status)
                assert.equals("custom-ak", resp._body.data.access_key)
                assert.equals("custom-sk", resp._body.data.secret_key)
            end)
        end)

        describe("disable", function()
            it("disables an existing credential", function()
                local ctx = {
                    params = {access_key = "existing-ak"},
                    response = resp,
                }
                handler:disable(ctx)
                assert.equals(200, resp._status)
                assert.equals("disabled", resp._body.data.status)
            end)

            it("returns 404 for non-existent credential", function()
                local ctx = {
                    params = {access_key = "nonexistent"},
                    response = resp,
                }
                handler:disable(ctx)
                assert.equals(404, resp._status)
                assert.equals(4003, resp._body.code)
            end)

            it("returns 400 when access_key is missing", function()
                local ctx = {
                    params = {},
                    response = resp,
                }
                handler:disable(ctx)
                assert.equals(400, resp._status)
            end)
        end)
    end)
end)
