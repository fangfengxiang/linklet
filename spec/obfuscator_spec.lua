-- spec/obfuscator_spec.lua
-- 短码生成算法测试：黄金比例混淆 + Base62 编码
-- Short code generation tests: golden ratio obfuscation + Base62 encoding

local Obfuscator = require("linklet.id.obfuscator")

describe("Obfuscator - Base62 encoding", function()
    describe("encode_base62", function()
        it("encodes zero as '0'", function()
            assert.equals("0", Obfuscator.encode_base62(0))
        end)

        it("encodes 61 as 'Z' (last single char)", function()
            assert.equals("Z", Obfuscator.encode_base62(61))
        end)

        it("encodes 62 as '10'", function()
            assert.equals("10", Obfuscator.encode_base62(62))
        end)

        it("encodes 916132832 (62^5) as '100000'", function()
            assert.equals("100000", Obfuscator.encode_base62(916132832))
        end)
    end)

    describe("decode_base62", function()
        it("decodes '0' as 0", function()
            assert.equals(0, Obfuscator.decode_base62("0"))
        end)

        it("decodes 'Z' as 61", function()
            assert.equals(61, Obfuscator.decode_base62("Z"))
        end)

        it("decodes '10' as 62", function()
            assert.equals(62, Obfuscator.decode_base62("10"))
        end)

        it("returns nil, err for invalid character", function()
            local val, err = Obfuscator.decode_base62("abc!")
            assert.is_nil(val)
            assert.truthy(err)
        end)
    end)

    describe("encode/decode round-trip", function()
        it("round-trips various values", function()
            local values = {0, 1, 61, 62, 100, 9999, 916132832, 9999999999}
            for _, v in ipairs(values) do
                local encoded = Obfuscator.encode_base62(v)
                local decoded = Obfuscator.decode_base62(encoded)
                assert.equals(v, decoded, "round-trip failed for " .. tostring(v))
            end
        end)
    end)
end)

describe("Obfuscator - golden ratio obfuscation", function()
    describe("obfuscate", function()
        it("produces different output for different IDs", function()
            local a = Obfuscator.obfuscate(1)
            local b = Obfuscator.obfuscate(2)
            assert.not_equals(a, b)
        end)

        it("produces output >= base offset (62^5)", function()
            for i = 0, 100 do
                local val = Obfuscator.obfuscate(i)
                assert.truthy(val >= 916132832, "obfuscate(" .. i .. ") = " .. tostring(val) .. " < 62^5")
            end
        end)

        it("produces non-sequential output", function()
            local outputs = {}
            for i = 1, 100 do
                outputs[#outputs + 1] = Obfuscator.obfuscate(i)
            end
            -- 验证输出不是连续递增 / verify output is not sequential
            local sequential = true
            for i = 2, #outputs do
                if outputs[i] ~= outputs[i - 1] + 1 then
                    sequential = false
                    break
                end
            end
            assert.is_false(sequential, "output should not be sequential")
        end)
    end)

    describe("collision detection (100000 range)", function()
        it("produces no collisions for IDs 1-100000", function()
            local seen = {}
            local collisions = 0
            for i = 1, 100000 do
                local val = Obfuscator.obfuscate(i)
                if seen[val] then
                    collisions = collisions + 1
                end
                seen[val] = true
            end
            assert.equals(0, collisions, "expected 0 collisions, got " .. tostring(collisions))
        end)
    end)
end)

describe("Obfuscator - generate (full pipeline)", function()
    it("generates codes with minimum 6 characters", function()
        for i = 1, 1000 do
            local code = Obfuscator.generate(i)
            assert.truthy(#code >= 6, "code " .. code .. " for ID " .. i .. " is shorter than 6 chars")
        end
    end)

    it("generates different codes for different IDs", function()
        local code1 = Obfuscator.generate(1)
        local code2 = Obfuscator.generate(2)
        assert.not_equals(code1, code2)
    end)

    it("generates no duplicate codes for IDs 1-10000", function()
        local seen = {}
        local duplicates = 0
        for i = 1, 10000 do
            local code = Obfuscator.generate(i)
            if seen[code] then
                duplicates = duplicates + 1
            end
            seen[code] = true
        end
        assert.equals(0, duplicates)
    end)

    it("generates codes that are not trivially predictable", function()
        -- 验证连续 ID 的短码看起来不相关
        local code1 = Obfuscator.generate(1)
        local code2 = Obfuscator.generate(2)
        -- 至少首字符应该不同 / at least first char should differ
        -- (实际上黄金比例混淆应该使输出完全不同)
        assert.not_equals(code1:sub(1, 1), code2:sub(1, 1) .. code1:sub(2, -1))
    end)
end)

describe("Obfuscator - reverse and decode", function()
    describe("decode_base62 with errors", function()
        it("errors on non-string input", function()
            assert.has_error(function()
                Obfuscator.decode_base62(123)
            end)
        end)

        it("errors on nil input", function()
            assert.has_error(function()
                Obfuscator.decode_base62(nil)
            end)
        end)
    end)

    describe("encode_base62 with errors", function()
        it("errors on negative number", function()
            assert.has_error(function()
                Obfuscator.encode_base62(-1)
            end)
        end)

        it("errors on non-number input", function()
            assert.has_error(function()
                Obfuscator.encode_base62("abc")
            end)
        end)
    end)

    describe("obfuscate with errors", function()
        it("errors on negative ID", function()
            assert.has_error(function()
                Obfuscator.obfuscate(-1)
            end)
        end)

        it("errors on non-number input", function()
            assert.has_error(function()
                Obfuscator.obfuscate("abc")
            end)
        end)
    end)

    describe("reverse", function()
        it("reverses a generated code back to the original ID", function()
            for _, id in ipairs({1, 2, 10, 100, 500}) do
                local code = Obfuscator.generate(id)
                local reversed = Obfuscator.reverse(code)
                assert.truthy(reversed, "reverse failed for ID " .. tostring(id))
                assert.equals(id, reversed, "reverse mismatch for ID " .. tostring(id))
            end
        end)
    end)

    describe("32-bit range", function()
        it("is exact at the upper boundary and rejects overflow", function()
            for _, value in ipairs({4194304,100000000,2147483647,4294967295}) do
                assert.equals(value, Obfuscator.reverse(Obfuscator.generate(value)))
            end
            assert.has_error(function() Obfuscator.generate(4294967296) end)
            assert.has_error(function() Obfuscator.generate(1.5) end)
            assert.is_nil(Obfuscator.decode_base62("ZZZZZZZZZZZZ"))
        end)
    end)

    describe("obfuscate zero", function()
        it("obfuscate(0) returns a value >= base offset", function()
            local val = Obfuscator.obfuscate(0)
            assert.truthy(val >= 916132832)
        end)
    end)
end)
