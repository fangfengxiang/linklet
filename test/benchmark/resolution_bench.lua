-- Run under OpenResty: resty -I lib test/benchmark/resolution_bench.lua
local cache = require("linklet.cache.local").new("benchmark_cache")
local resolver = require("linklet.gateway.resolver").new({
    cache = cache, resolution_repository = {find_for_resolution = function() error("unexpected cache miss") end},
})
assert(cache:set("link:s.example.com:bench01", "https://example.com", 60))
local iterations = 100000
local start = ngx.now()
for _ = 1, iterations do
    assert(resolver:resolve("s.example.com", "bench01").cache_hit)
end
ngx.update_time()
ngx.say(string.format("cached resolution: %d operations in %.6f seconds", iterations, ngx.now() - start))
