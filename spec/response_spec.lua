-- spec/response_spec.lua
-- 响应工具测试 / Response utility tests

local Response = require("lib.response")

describe("Response", function()
    local resp

    before_each(function()
        resp = Response.new()
    end)

    describe("json", function()
        it("sets status and body", function()
            resp:json(200, {hello = "world"})
            assert.equals(200, resp._status)
            assert.same({hello = "world"}, resp._body)
        end)

        it("sets 404 status", function()
            resp:json(404, {error = "not found"})
            assert.equals(404, resp._status)
        end)
    end)

    describe("success", function()
        it("formats success response with code 0", function()
            resp:success({code = "aB9xK2"})
            assert.equals(200, resp._status)
            assert.equals(0, resp._body.code)
            assert.equals("success", resp._body.message)
            assert.equals("aB9xK2", resp._body.data.code)
        end)

        it("accepts custom status code", function()
            resp:success({id = 1}, 201)
            assert.equals(201, resp._status)
        end)
    end)

    describe("error_response", function()
        it("formats error response with non-zero code", function()
            resp:error_response(4001, "target_url is required")
            assert.equals(400, resp._status)
            assert.equals(4001, resp._body.code)
            assert.equals("target_url is required", resp._body.message)
            assert.equals(require("cjson.safe").null, resp._body.data)
        end)

        it("accepts custom HTTP status", function()
            resp:error_response(404, "not found", 404)
            assert.equals(404, resp._status)
        end)
    end)

    describe("not_found", function()
        it("returns 404 with message", function()
            resp:not_found("short link not found")
            assert.equals(404, resp._status)
            assert.equals(404, resp._body.code)
            assert.equals("short link not found", resp._body.message)
        end)

        it("uses default message", function()
            resp:not_found()
            assert.equals("not found", resp._body.message)
        end)
    end)

    describe("gone", function()
        it("returns 410", function()
            resp:gone("link expired")
            assert.equals(410, resp._status)
            assert.equals("link expired", resp._body.message)
        end)
    end)

    describe("internal_error", function()
        it("returns 500", function()
            resp:internal_error("database connection failed")
            assert.equals(500, resp._status)
            assert.equals("database connection failed", resp._body.message)
        end)
    end)

    describe("_encode_json fallback", function()
        it("encodes nil as null", function()
            assert.equals("null", Response._encode_json(nil))
        end)

        it("encodes boolean", function()
            assert.equals("true", Response._encode_json(true))
            assert.equals("false", Response._encode_json(false))
        end)

        it("encodes string", function()
            assert.equals('"hello"', Response._encode_json("hello"))
        end)

        it("encodes number", function()
            local result = Response._encode_json(42)
            assert.equals("42", result)
        end)

        it("encodes array table", function()
            local result = Response._encode_json({1, 2, 3})
            assert.equals("[1,2,3]", result)
        end)

        it("encodes object table", function()
            local result = Response._encode_json({name = "test", id = 1})
            assert.equals("test", require("cjson.safe").decode(result).name)
            assert.equals(1, require("cjson.safe").decode(result).id)
        end)

        it("encodes empty array", function()
            local result = Response._encode_json({})
            -- Empty table treated as object, not array
            assert.equals("{}", result)
        end)

        it("encodes nested tables", function()
            local result = Response._encode_json({items = {1, 2}})
            assert.truthy(result:find('"items"'))
            assert.truthy(result:find('%[1,2%]'))
        end)

        it("encodes table with non-number keys", function()
            local result = Response._encode_json({a = 1, b = true})
            assert.truthy(result:find('"a"'))
            assert.truthy(result:find('"b"'))
        end)

        it("encodes unsupported type as null", function()
            local result = Response._encode_json(function() end)
            assert.equals("null", result)
        end)
    end)
end)
