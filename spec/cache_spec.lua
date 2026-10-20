-- spec/cache_spec.lua
-- 缓存测试 / Cache tests

local Cache = require("linklet.cache.local")

describe("Cache", function()
    local cache

    before_each(function()
        cache = Cache.new("test_cache")
        -- 注入 mock dict
        local store = {}
        cache:set_dict({
            get = function(_, key) return store[key] end,
            set = function(_, key, value) store[key] = value; return true end,
            delete = function(_, key) store[key] = nil; return true end,
        })
        cache._store = store
    end)

    describe("set and get", function()
        it("stores and retrieves a value", function()
            cache:set("key1", "value1")
            assert.equals("value1", cache:get("key1"))
        end)

        it("returns nil for missing key", function()
            assert.is_nil(cache:get("nonexistent"))
        end)

        it("overwrites existing value", function()
            cache:set("key1", "value1")
            cache:set("key1", "value2")
            assert.equals("value2", cache:get("key1"))
        end)
    end)

    describe("delete", function()
        it("removes a value", function()
            cache:set("key1", "value1")
            cache:delete("key1")
            assert.is_nil(cache:get("key1"))
        end)

        it("does not error on missing key", function()
            cache:delete("nonexistent")
            -- no error thrown
        end)
    end)

    describe("get_or_set", function()
        it("returns cached value without calling factory", function()
            cache:set("key1", "cached")
            local factory_called = false
            local result = cache:get_or_set("key1", function()
                factory_called = true
                return "new"
            end)
            assert.equals("cached", result)
            assert.is_false(factory_called)
        end)

        it("calls factory and caches result on miss", function()
            local call_count = 0
            local factory = function()
                call_count = call_count + 1
                return "computed"
            end

            local result1 = cache:get_or_set("key1", factory)
            local result2 = cache:get_or_set("key1", factory)

            assert.equals("computed", result1)
            assert.equals("computed", result2)
            assert.equals(1, call_count)
        end)
    end)

    describe("with TTL", function()
        it("passes TTL to dict set", function()
            local received_ttl
            local store = {}
            cache:set_dict({
                get = function(_, key) return store[key] end,
                set = function(_, key, value, ttl)
                    received_ttl = ttl
                    store[key] = value
                    return true
                end,
                delete = function(_, key) store[key] = nil end,
            })

            cache:set("key1", "value1", 300)
            assert.equals(300, received_ttl)
        end)
    end)
end)
