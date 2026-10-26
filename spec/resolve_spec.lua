local helper = require("helper")
local slds = require("slds")
local Resolver = require("linklet.gateway.resolver")
local Handler = require("linklet.gateway.handler")

local function projection(fields)
    fields = fields or {}
    return {
        link = assert(slds.ShortLink.new({
            namespace = "linklet", code = "aB9xK2", target = "https://example.com/page",
            status = fields.status or slds.Lifecycle.ACTIVE,
            expires_at = fields.expires_at, metadata = {group_id = 1},
        })),
        domain = fields.domain or "s.example.com",
        domain_status = fields.domain_status or 2,
        domain_deleted = fields.domain_deleted or false,
        tenant_status = fields.tenant_status,
        group_status = fields.group_status,
    }
end

describe("Gateway resolution", function()
    local cache, repository, resolver, queries
    before_each(function()
        queries = 0
        cache = helper.mock_cache()
        cache.set_for_generation = function(self, key, value, ttl, generation)
            if generation == self:generation() then return self:set(key, value, ttl) end
            return true
        end
        repository = {find_for_resolution = function()
            queries = queries + 1
            return projection()
        end}
        resolver = Resolver.new({resolution_repository = repository, cache = cache, now = function() return 100 end})
    end)

    it("returns a resolution value, caches it and skips storage on a healthy hit", function()
        local result = assert(resolver:resolve("s.example.com", "aB9xK2"))
        assert.equals("https://example.com/page", result.target_url)
        assert.equals(1, queries)
        result = assert(resolver:resolve("S.Example.com.:443", "aB9xK2"))
        assert.is_true(result.cache_hit)
        assert.equals(1, queries)
    end)

    it("isolates hosts even when the code has a warm cache entry", function()
        assert(resolver:resolve("s.example.com", "aB9xK2"))
        local result, err = resolver:resolve("other.example.com", "aB9xK2")
        assert.is_nil(result)
        assert.equals("not_found", err.kind)
        assert.is_nil(cache:get("link:other.example.com:aB9xK2"))
    end)

    it("rejects invalid host and missing code before reading storage", function()
        for _, args in ipairs({{false, "aB9xK2"}, {"a..example.com", "aB9xK2"}, {"s.example.com", ""}}) do
            local result, err = resolver:resolve(args[1], args[2])
            assert.is_nil(result)
            assert.equals("not_found", err.kind)
        end
        assert.equals(0, queries)
    end)

    it("distinguishes missing links from storage failures", function()
        repository.find_for_resolution = function() return nil end
        local result, err = resolver:resolve("s.example.com", "aB9xK2")
        assert.is_nil(result)
        assert.equals("not_found", err.kind)
        repository.find_for_resolution = function() return nil, "unavailable" end
        result, err = resolver:resolve("s.example.com", "aB9xK2")
        assert.is_nil(result)
        assert.equals("unavailable", err.kind)
    end)

    it("uses SLDS lifecycle and deadline decisions without tenant or group status", function()
        repository.find_for_resolution = function()
            return projection({tenant_status = 2, group_status = 2})
        end
        assert(resolver:resolve("s.example.com", "aB9xK2"))
        for _, status in ipairs({slds.Lifecycle.DISABLED, slds.Lifecycle.DELETED}) do
            repository.find_for_resolution = function() return projection({status = status}) end
            local cold = Resolver.new({resolution_repository = repository, now = function() return 100 end})
            local result, err = cold:resolve("s.example.com", "aB9xK2")
            assert.is_nil(result)
            assert.equals("gone", err.kind)
        end
        repository.find_for_resolution = function() return projection({expires_at = 100}) end
        local cold = Resolver.new({resolution_repository = repository, now = function() return 100 end})
        local result, err = cold:resolve("s.example.com", "aB9xK2")
        assert.is_nil(result)
        assert.equals("link expired", err.message)
    end)

    it("truncates cache TTL at fractional expiration and respects a shorter configured TTL", function()
        local observed_ttl
        cache.set = function(_, _, _, ttl) observed_ttl = ttl; return true end
        repository.find_for_resolution = function() return projection({expires_at = 100.25}) end
        assert(resolver:resolve("s.example.com", "aB9xK2"))
        assert.equals(0.25, observed_ttl)
        resolver.cache_ttl = 0.1
        assert(resolver:resolve("s.example.com", "aB9xK2"))
        assert.equals(0.1, observed_ttl)
    end)

    it("rejects an unavailable or deleted domain and checks host before revealing link state", function()
        for _, fields in ipairs({{domain_status = 3}, {domain_deleted = true}}) do
            repository.find_for_resolution = function() return projection(fields) end
            local result, err = resolver:resolve("s.example.com", "aB9xK2")
            assert.is_nil(result)
            assert.equals("gone", err.kind)
            result, err = resolver:resolve("wrong.example.com", "aB9xK2")
            assert.is_nil(result)
            assert.equals("not_found", err.kind)
        end
    end)

    it("does not refill cache when invalidation races a storage lookup", function()
        local generation = 0
        cache.generation = function() return generation end
        repository.find_for_resolution = function()
            generation = generation + 1
            return projection()
        end
        assert(resolver:resolve("s.example.com", "aB9xK2"))
        assert.is_nil(cache:get("link:s.example.com:aB9xK2"))
    end)

    it("cannot refill the active generation if invalidation occurs immediately before the write", function()
        local Cache = require("linklet.cache.local")
        local values = {["cache:generation"] = 0}
        local dict = {
            get = function(_, key) return values[key] end,
            set = function(_, key, value) values[key] = value; return true end,
            delete = function(_, key) values[key] = nil end,
            incr = function(_, key, amount, initial)
                values[key] = (values[key] or initial) + amount
                return values[key]
            end,
        }
        local first, second = Cache.new(), Cache.new()
        first:set_dict(dict); second:set_dict(dict)
        local write = first.set_for_generation
        first.set_for_generation = function(self, key, value, ttl, generation)
            assert(second:invalidate("aB9xK2"))
            return write(self, key, value, ttl, generation)
        end
        local racing = Resolver.new({resolution_repository = repository, cache = first})
        assert(racing:resolve("s.example.com", "aB9xK2"))
        assert.equals(1, first:generation())
        assert.is_nil(second:get("link:s.example.com:aB9xK2"))
        assert.equals("https://example.com/page", values["link:s.example.com:aB9xK2:g0"])
    end)

    it("can resolve without a cache", function()
        local cold = Resolver.new({resolution_repository = repository})
        local result = assert(cold:resolve("s.example.com", "aB9xK2"))
        assert.equals("https://example.com/page", result.target_url)
    end)

    it("requires a finite positive TTL and an explicit read capability", function()
        assert.has_error(function() Resolver.new({cache_ttl = 0}) end)
        assert.has_error(function() Resolver.new({}) end)
    end)
end)

describe("Gateway HTTP adapter", function()
    it("maps the successful resolution to an empty 302 response", function()
        local response = helper.mock_response()
        local handler = Handler.new({resolve = function(_, host, code)
            assert.equals("s.example.com", host)
            assert.equals("aB9xK2", code)
            return {target_url = "https://example.com"}
        end})
        assert(handler:handle({method = "GET", uri = "/aB9xK2", host = "s.example.com", response = response}))
        assert.equals(302, response._status)
        assert.equals("https://example.com", response._location)
        assert.is_true(response.sent)
    end)

    it("maps resolver errors to transport responses", function()
        for kind, status in pairs({not_found = 404, gone = 410, unavailable = 500}) do
            local response = helper.mock_response()
            local handler = Handler.new({resolve = function() return nil, {kind = kind, message = "rejected"} end})
            handler:handle({method = "GET", uri = "/aB9xK2", host = "s.example.com", response = response})
            assert.equals(status, response._status)
        end
    end)

    it("rejects non-Gateway paths and methods before invoking the resolver", function()
        local handler = Handler.new({resolve = function() error("must not resolve") end})
        for _, request in ipairs({{method = "POST", uri = "/aB9xK2"}, {method = "GET", uri = "/api/v1/admin/list"}}) do
            request.response = helper.mock_response()
            handler:handle(request)
            assert.equals(404, request.response._status)
        end
    end)
end)
