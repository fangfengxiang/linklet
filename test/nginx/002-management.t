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
=== TEST 1: own link disable with only code succeeds; repeat disable returns 404
--- test_code
local code = a.create()
local status = a.request("PUT","/api/v1/shorten/disable",require("cjson").encode({code=code}))
assert(status == 200, "disable status " .. status)
assert(a.request("PUT","/api/v1/shorten/disable",require("cjson").encode({code=code})) == 404)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 2: another tenant cannot disable an existing public code
--- test_code
local code = a.create()
local status = a.request("PUT","/api/v1/shorten/disable",require("cjson").encode({code=code}),{ak="other-ak"})
assert(status == 404, "cross-tenant disable status " .. status)
assert(tonumber(a.deps.link_model:find_by_code(code).status) == 1)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 3: validation errors are 400 JSON and foreign group is 403
--- test_code
local status, body = a.request("POST","/api/v1/shorten/create",'{"group_id":1}')
assert(status == 400 and body.code ~= 0 and body.data == ngx.null)
assert(a.request("POST","/api/v1/shorten/create",'{"target_url":"https://example.com","group_id":2}') == 403)
assert(a.request("PUT","/api/v1/shorten/disable",'{}') == 400)
assert(a.request("POST","/api/v1/shorten/create",'{"target_url":"javascript:alert(1)","group_id":1}') == 400)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 4: full short URL includes scheme; disabled group rejects further creation
--- test_code
local status, body = a.request("POST","/api/v1/shorten/gen",'{"target_url":"https://example.com","group_id":1}')
assert(status == 200 and body.data.short_url == "https://s.example.com/" .. body.data.code)
assert(not a.deps.group_model:configure(1,2))
assert(a.deps.db:query("UPDATE sl_group SET status=2 WHERE group_id=1"))
assert(a.request("POST","/api/v1/shorten/gen",'{"target_url":"https://example.com","group_id":1}') == 404)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 5: false and array fields return 400; database errors are not reported as missing links
--- test_code
assert(a.request("POST","/api/v1/shorten/create",'{"target_url":false,"group_id":1}') == 400)
assert(a.request("POST","/api/v1/shorten/create",'{"target_url":"https://example.com","group_id":[]}') == 400)
local original = a.deps.group_model.find_by_id_with_domain
a.deps.group_model.find_by_id_with_domain = function() return nil,"unavailable" end
assert(a.request("POST","/api/v1/shorten/create",'{"target_url":"https://example.com","group_id":1}') == 500)
a.deps.group_model.find_by_id_with_domain = original
a.deps.link_model.disable = function() return nil,"unavailable" end
assert(a.request("PUT","/api/v1/shorten/disable",'{"code":"missingCode"}') == 500)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]
