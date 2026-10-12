use Test::Nginx::Socket::Lua 'no_plan';
use lib 'test/nginx/lib';
use LinkletTest;
repeat_each(1);
no_shuffle();
add_block_preprocessor(sub {
    my $block = shift;
    my $before = <<'CONF';
        include __ROOT__/conf/locations.conf;
        location = /t { content_by_lua_block {
            local a = require("acceptance")
            a.setup()
CONF
    my $after = <<'CONF';
            ngx.say("accepted")
        } }
CONF
    $before =~ s/__ROOT__/$ENV{LINKLET_ROOT}/g;
    $block->set_value('config', $before . $block->test_code . $after);

});
run_tests();
__DATA__
=== TEST 1: miss writes cache; hit performs no model query; disable returns 410
--- test_code
local code = a.create()
local status, _, headers = a.request("GET","/" .. code)
assert(status == 302 and headers:find("Location: https://example.com/page",1,true))
assert(a.deps.cache:get("link:" .. code) == "https://example.com/page")
local original = a.deps.link_model.find_by_code
local queries = 0
a.deps.link_model.find_by_code = function(...) queries = queries+1; return original(...) end
assert(a.request("GET","/" .. code) == 302 and queries == 0)
assert(a.request("PUT","/api/v1/shorten/disable",require("cjson").encode({code=code})) == 200)
assert(a.request("GET","/" .. code) == 410 and queries == 1)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 2: a past PostgreSQL TIMESTAMPTZ returns 410, including an offset
--- test_code
local code = a.create({target_url="https://example.com",scene_id=1,expires_at="2001-01-01T08:00:00+08:00"})
assert(a.request("GET","/" .. code) == 410)
assert(not a.deps.cache:get("link:" .. code))
assert(a.request("GET","/missingCode") == 404)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 3: cached link expires at the business deadline, before the configured TTL
--- test_code
local code = a.create()
assert(a.deps.db:query("UPDATE sl_link SET expires_at = NOW() + INTERVAL '0.5 seconds' WHERE code = $1",code))
assert(a.request("GET","/" .. code) == 302)
ngx.sleep(0.6)
assert(a.request("GET","/" .. code) == 410)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 4: a lookup cannot refill cache after a concurrent disable
--- test_code
local code = a.create()
local original = a.deps.link_model.find_by_code
local started = require("ngx.semaphore").new()
local resume = require("ngx.semaphore").new()
a.deps.link_model.find_by_code = function(...)
    local row = original(...)
    started:post(1)
    assert(resume:wait(5))
    return row
end
local lookup = ngx.thread.spawn(function() return a.request("GET","/" .. code) end)
assert(started:wait(5))
assert(a.request("PUT","/api/v1/shorten/disable",require("cjson").encode({code=code})) == 200)
resume:post(1)
assert(ngx.thread.wait(lookup))
a.deps.link_model.find_by_code = original
assert(not a.deps.cache:get("link:" .. code))
assert(a.request("GET","/" .. code) == 410)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 5: independent instance caches synchronize; stale synchronization bypasses cache
--- test_code
local code = a.create()
local other = require("lib.cache").new("other_cache")
local sync = require("lib.cache_sync").new(a.deps.db,other,0.05)
assert(sync:tick())
assert(other:set("link:" .. code,"https://example.com/page",300))
assert(other:get("link:" .. code))
assert(a.request("PUT","/api/v1/shorten/disable",require("cjson").encode({code=code})) == 200)
assert(sync:tick())
assert(not other:get("link:" .. code))
assert(other:set("link:staleCode","https://example.com/page",300))
ngx.sleep(0.12)
assert(not other:get("link:staleCode"))
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]
