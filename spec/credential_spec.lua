-- spec/credential_spec.lua
-- 租户凭证模型测试 / Tenant credential model tests

local helper = require("helper")
local TenantCredential = require("linklet.repository.credential")

describe("TenantCredential", function()
    local model, db

    local crypto
    before_each(function()
        crypto = {
            encrypt = function(value) return "mock:" .. value end,
            decrypt = function(value) return value:sub(6) end,
        }
        db = helper.mock_db(function()
            return {{id = 1, tenant_id = 1, access_key = "test-ak", status = 1}}
        end)
        model = TenantCredential.new(db, crypto)
    end)

    describe("create", function()
        it("creates a credential with encrypted SK", function()
            local captured_args
            db.query = function(self, sql, ...)
                captured_args = {...}
                return {{id = 1, tenant_id = 1, access_key = "test-ak", status = 1}}
            end

            local row = model:create(1, "test-ak", "my-secret-key")

            assert.truthy(row)
            assert.equals(1, row.tenant_id)
            assert.equals("test-ak", row.access_key)
            -- The second argument after tenant_id and access_key should be encrypted SK
            assert.not_equals("my-secret-key", captured_args[3])
        end)
    end)

    describe("find_by_access_key", function()
        it("finds credential by AK", function()
            db.query = function(self, sql, ...)
                return {{id = 1, tenant_id = 1, access_key = "test-ak",
                         secret_key_enc = crypto.encrypt("test-sk"), status = 1}}
            end

            local row = model:find_by_access_key("test-ak")

            assert.truthy(row)
            assert.equals(1, row.tenant_id)
            assert.equals("test-sk", row.secret_key)
            assert.is_nil(row.secret_key_enc)
        end)

        it("returns nil when AK not found", function()
            db.query = function() return {} end

            local row = model:find_by_access_key("nonexistent")
            assert.is_nil(row)
        end)
    end)

    describe("disable", function()
        it("disables a credential", function()
            db.query = function() return {{id = 1}} end

            local row = model:disable("test-ak")
            assert.truthy(row)
        end)

        it("returns nil when credential not found", function()
            db.query = function() return {} end

            local row = model:disable("nonexistent")
            assert.is_nil(row)
        end)
    end)

    describe("set_encryption_key", function()
        it("rejects a missing or weak deployment key", function()
            assert.has_error(function() TenantCredential.set_encryption_key(nil) end)
            assert.has_error(function() TenantCredential.set_encryption_key("weak") end)
        end)
    end)
end)
