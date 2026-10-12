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
=== TEST 1: real HMAC rejects body/query tampering and accepts signed query
--- test_code
local body = '{"target_url":"https://example.com","scene_id":1}'
assert(a.request("POST","/api/v1/shorten/create",body,{signed_body=body .. " "}) == 401)
assert(a.request("POST","/api/v1/shorten/create?scene_id=2",'{"target_url":"https://example.com"}',{signed_uri="/api/v1/shorten/create?scene_id=1"}) == 401)
assert(a.request("POST","/api/v1/shorten/create?scene_id=1",'{"target_url":"https://example.com"}') == 200)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 2: missing or stale timestamp, wrong signature and disabled credentials return 401
--- test_code
local body = '{"target_url":"https://example.com","scene_id":1}'
assert(a.request("POST","/api/v1/shorten/create",body,{no_auth=true}) == 401)
assert(a.request("POST","/api/v1/shorten/create",body,{no_timestamp=true}) == 401)
assert(a.request("POST","/api/v1/shorten/create",body,{timestamp="1000"}) == 401)
assert(a.request("POST","/api/v1/shorten/create",body,{signature="wrong"}) == 401)
assert(a.deps.credential_model:disable(a.ak))
assert(a.request("POST","/api/v1/shorten/create",body) == 401)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 3: AES-GCM uses random nonce, detects tampering, refuses legacy XOR and missing key
--- test_code
local c = require("lib.crypto")
local one = assert(c.encrypt(a.sk))
local two = assert(c.encrypt(a.sk))
assert(one ~= two and one:sub(1,3) == "v1:" and c.decrypt(one) == a.sk)
local raw = ngx.decode_base64(one:sub(4))
local corrupted = "v1:" .. ngx.encode_base64(raw:sub(1,-2) .. string.char((raw:byte(-1)+1)%256))
assert(not c.decrypt(corrupted))
assert(not c.decrypt("180c1d1f4116114e1600124c1e090d005b5548"))
assert(not pcall(c.configure,"short-key"))
local stored = assert(a.deps.db:query("SELECT secret_key_enc FROM sl_tenant_credential WHERE access_key = $1",a.ak))[1].secret_key_enc
assert(stored:sub(1,3) == "v1:" and c.decrypt(stored) == a.sk)
assert(#assert(c.random_key()) == 64)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 4: malformed JSON and scalar bodies return 400; disk-buffered bodies are signed in full
--- test_code
assert(a.request("POST","/api/v1/shorten/create","{bad}") == 400)
assert(a.request("POST","/api/v1/shorten/create","true") == 400)
assert(a.request("POST","/api/v1/shorten/create","[]") == 400)
local body = require("cjson").encode({target_url="https://example.com",scene_id=1,padding=string.rep("x",32768)})
assert(a.request("POST","/api/v1/shorten/create",body) == 200)
assert(a.request("POST","/api/v1/shorten/create",body,{signed_body=""}) == 401)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]
