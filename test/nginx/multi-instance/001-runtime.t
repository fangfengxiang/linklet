use Test::Nginx::Socket::Lua 'no_plan';
use lib 'test/nginx/lib';
use LinkletTest;
repeat_each(1);
run_tests();
__DATA__
=== TEST 1: production containers share IDs and invalidate independent caches
--- http_config
resolver 127.0.0.11 ipv6=off;
--- config
location /t {
    content_by_lua_block {
        local a = require("acceptance")
        a.setup()
        local first = {host=os.getenv("LINKLET_MULTI_A") or "runtime-a",port=80}
        local second = {host=os.getenv("LINKLET_MULTI_B") or "runtime-b",port=80}
        assert(a.request("GET","/health",nil,first) == 200)
        assert(a.request("GET","/health",nil,second) == 200)
        -- These requests originate outside each runtime's loopback boundary.
        assert(a.request("GET","/api/v1/admin/tenant/list",nil,first)==403)
        assert(a.request("GET","/api/v1/admin/tenant/list",nil,second)==403)
        local body = '{"target_url":"https://example.com/multi-instance","group_id":1}'
        local status, response = a.request("POST","/api/v1/shorten/create",body,first)
        assert(status == 200, "create on first instance failed")
        local code = response.data.code
        status, response = a.request("POST","/api/v1/shorten/create",body,second)
        assert(status == 200 and response.data.code ~= code, "instances must reserve disjoint segments")
        assert(a.request("GET","/" .. code,nil,first) == 302)
        assert(a.request("GET","/" .. code,nil,second) == 302)
        assert(a.request("PUT","/api/v1/shorten/disable",require("cjson").encode({code=code}),first) == 200)
        assert(a.request("GET","/" .. code,nil,first) == 410)
        ngx.sleep(1.1)
        assert(a.request("GET","/" .. code,nil,second) == 410, "second instance cache still redirects")
        ngx.say("multi-instance accepted")
    }
}
--- request
GET /t
--- response_body
multi-instance accepted
--- no_error_log
[error]
