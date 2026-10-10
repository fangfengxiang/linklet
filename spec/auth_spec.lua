-- spec/auth_spec.lua
-- 认证中间件测试 / Auth middleware tests

local helper = require("helper")
local AuthMiddleware = require("middleware.auth")

describe("AuthMiddleware", function()
    local auth_mw, mock_credential_model, resp, req

    before_each(function()
        mock_credential_model = {
            find_by_access_key = function(self, ak)
                return {
                    tenant_id = 1,
                    access_key = ak,
                    secret_key = "test-secret-key",
                    status = 1,
                }
            end,
        }
        -- Monkey-patch the module-level verify_signature
        local TenantCredential = require("models.tenant_credential")
        TenantCredential.verify_signature = function(sk, str, sig)
            return sk == "test-secret-key" and sig == "valid-signature"
        end

        auth_mw = AuthMiddleware.new(mock_credential_model)
        resp = helper.mock_response()
    end)

    describe("valid authentication", function()
        it("authenticates with valid AK and signature", function()
            req = helper.mock_request("POST", "/api/v1/shorten/create", {}, {
                ["X-Access-Key"] = "test-ak",
                ["X-Signature"] = "valid-signature",
                ["X-Timestamp"] = tostring(os.time()),
            })

            local ctx = {
                request = req,
                response = resp,
            }

            local next_called = false
            local result, err = auth_mw:handle(ctx, function()
                next_called = true
                return true
            end)

            assert.truthy(next_called)
            assert.equals(1, ctx.tenant_id)
            assert.equals("test-ak", ctx.access_key)
        end)
    end)

    describe("invalid authentication", function()
        it("returns error when AK is missing", function()
            req = helper.mock_request("POST", "/api/v1/shorten/create", {}, {})

            local ctx = {request = req, response = resp}

            local next_called = false
            local result, err = auth_mw:handle(ctx, function()
                next_called = true
                return true
            end)

            assert.is_false(next_called)
            assert.truthy(err)
            assert.matches("access key", err)
        end)

        it("returns error when signature is missing", function()
            req = helper.mock_request("POST", "/api/v1/shorten/create", {}, {
                ["X-Access-Key"] = "test-ak",
            })

            local ctx = {request = req, response = resp}

            local result, err = auth_mw:handle(ctx, function() return true end)

            assert.truthy(err)
            assert.matches("signature", err)
        end)

        it("returns error for invalid signature", function()
            req = helper.mock_request("POST", "/api/v1/shorten/create", {}, {
                ["X-Access-Key"] = "test-ak",
                ["X-Signature"] = "wrong-signature",
                ["X-Timestamp"] = tostring(os.time()),
            })

            local ctx = {request = req, response = resp}

            local result, err = auth_mw:handle(ctx, function() return true end)

            assert.truthy(err)
            assert.matches("invalid signature", err)
        end)

        it("returns error for unknown AK", function()
            mock_credential_model.find_by_access_key = function() return nil end

            req = helper.mock_request("POST", "/api/v1/shorten/create", {}, {
                ["X-Access-Key"] = "unknown-ak",
                ["X-Signature"] = "any-signature",
                ["X-Timestamp"] = tostring(os.time()),
            })

            local ctx = {request = req, response = resp}

            local result, err = auth_mw:handle(ctx, function() return true end)

            assert.truthy(err)
            assert.matches("invalid access key", err)
        end)
    end)

    describe("disabled credential", function()
        it("returns error for disabled credential", function()
            mock_credential_model.find_by_access_key = function()
                return nil  -- disabled credentials return nil (status=1 filter)
            end

            req = helper.mock_request("POST", "/api/v1/shorten/create", {}, {
                ["X-Access-Key"] = "disabled-ak",
                ["X-Signature"] = "any-sig",
                ["X-Timestamp"] = tostring(os.time()),
            })

            local ctx = {request = req, response = resp}

            local result, err = auth_mw:handle(ctx, function() return true end)

            assert.truthy(err)
        end)
    end)

    describe("single authentication pass", function()
        it("tenant_id propagates via context", function()
            req = helper.mock_request("POST", "/api/v1/shorten/create", {}, {
                ["X-Access-Key"] = "test-ak",
                ["X-Signature"] = "valid-signature",
                ["X-Timestamp"] = tostring(os.time()),
            })

            local ctx = {request = req, response = resp}

            auth_mw:handle(ctx, function()
                -- handler should see tenant_id from context
                assert.equals(1, ctx.tenant_id)
                return true
            end)
        end)
    end)
end)
