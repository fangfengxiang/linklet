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
=== TEST 1: real production locations expose readiness and liveness independently
--- test_code
local status, _, _, body = a.request("GET","/health",nil,{no_auth=true})
assert(status == 200 and body == "ok\n")
local db = a.deps.db
local original = db.query
db.query = function() return nil,"unavailable" end
assert(a.request("GET","/health",nil,{no_auth=true}) == 503)
assert(a.request("GET","/health/live",nil,{no_auth=true}) == 200)
db.query = original
assert(a.request("GET","/health",nil,{no_auth=true}) == 200)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 2: loopback admin creates a tenant and secure credential; disabled credential stops access
--- test_code
local status, body = a.request("POST","/api/v1/admin/tenant/create",'{"name":"admin-created"}',{no_auth=true})
assert(status == 200, "tenant create: " .. status .. " " .. require("cjson").encode(body))
local tenant = body.data.id
status, body = a.request("POST","/api/v1/admin/credential/create",require("cjson").encode({tenant_id=tenant}),{no_auth=true})
assert(status == 200 and #body.data.access_key == 64 and #body.data.secret_key == 64)
local stored = assert(a.deps.credential_model:find_by_access_key(body.data.access_key))
assert(stored.secret_key == body.data.secret_key)
assert(a.request("GET","/api/v1/admin/tenant/list",nil,{no_auth=true}) == 200)
assert(a.request("PUT","/api/v1/admin/credential/disable",require("cjson").encode({access_key=body.data.access_key}),{no_auth=true}) == 200)
assert(not a.deps.credential_model:find_by_access_key(body.data.access_key))
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 3: package entry point loads and inherited domain update is rejected by the database
--- test_code
assert(require("linklet") == require("linklet.app"))
local result = a.deps.domain_entry_model:update({domain="mutated.example.com"},"id = $2",{1})
assert(not result)
local row = a.deps.scene_model:find_by_id_with_domain(1)
assert(row.scene_id == 1 and row.domain == "s.example.com")
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]
