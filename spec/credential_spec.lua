-- spec/credential_spec.lua
-- 租户凭证模型测试 / Tenant credential model tests

local helper = require("helper")
local TenantCredential = require("linklet.repository.credential")

describe("TenantCredential", function()
    local model, db

    local encrypt, decrypt
    before_each(function()
        encrypt, decrypt = TenantCredential._encrypt, TenantCredential._decrypt
        TenantCredential._encrypt = function(value) return "mock:" .. value end
        TenantCredential._decrypt = function(value) return value:sub(6) end
        db = helper.mock_db(function(sql, ...)
            return {{id = 1, tenant_id = 1, access_key = "test-ak", status = 1}}
        end)
        model = TenantCredential.new(db)
    end)

    after_each(function()
        TenantCredential._encrypt, TenantCredential._decrypt = encrypt, decrypt
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
                         secret_key_enc = TenantCredential._encrypt("test-sk"), status = 1}}
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

    describe("verify_signature", function()
        it("returns false for nil parameters", function()
            assert.is_false(TenantCredential.verify_signature(nil, "str", "sig"))
            assert.is_false(TenantCredential.verify_signature("sk", nil, "sig"))
            assert.is_false(TenantCredential.verify_signature("sk", "str", nil))
        end)

        it("returns false for empty strings", function()
            assert.is_false(TenantCredential.verify_signature("", "str", "sig"))
            assert.is_false(TenantCredential.verify_signature("sk", "", "sig"))
            assert.is_false(TenantCredential.verify_signature("sk", "str", ""))
        end)
    end)

    describe("_hex_decode", function()
        it("decodes valid hex string", function()
            local decoded = TenantCredential._hex_decode("48656c6c6f")
            assert.equals("Hello", decoded)
        end)

        it("returns nil for odd-length hex", function()
            local decoded = TenantCredential._hex_decode("486")
            assert.is_nil(decoded)
        end)

        it("returns nil for invalid hex characters", function()
            local decoded = TenantCredential._hex_decode("xyz")
            assert.is_nil(decoded)
        end)

        it("returns nil for nil input", function()
            local decoded = TenantCredential._hex_decode(nil)
            assert.is_nil(decoded)
        end)
    end)

    describe("_constant_time_compare", function()
        it("returns true for equal strings", function()
            assert.is_true(TenantCredential._constant_time_compare("hello", "hello"))
        end)

        it("returns false for different strings", function()
            assert.is_false(TenantCredential._constant_time_compare("hello", "world"))
        end)

        it("returns false for different lengths", function()
            assert.is_false(TenantCredential._constant_time_compare("hello", "hi"))
        end)

        it("returns false for nil arguments", function()
            assert.is_false(TenantCredential._constant_time_compare(nil, "hello"))
            assert.is_false(TenantCredential._constant_time_compare("hello", nil))
        end)
    end)

    describe("set_encryption_key", function()
        it("rejects a missing or weak deployment key", function()
            assert.has_error(function() TenantCredential.set_encryption_key(nil) end)
            assert.has_error(function() TenantCredential.set_encryption_key("weak") end)
        end)
    end)
end)
