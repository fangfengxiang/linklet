-- Run under OpenResty: resty -I src test/benchmark/resolution_bench.lua
local cache = require("linklet.cache.local").new("benchmark_cache")
local handler = require("linklet.gateway.cache").new(cache)
assert(cache:set("link:bench01","https://example.com",60))
local function next_handler() return true end
local iterations = 100000
local start = ngx.now()
for _=1,iterations do
    local ctx = {params={code="bench01"}}
    assert(handler:handle(ctx,next_handler) and ctx.cache_hit)
end
ngx.update_time()
local elapsed = ngx.now()-start
ngx.say(string.format("cache handler: %d operations in %.6f seconds",iterations,elapsed))
