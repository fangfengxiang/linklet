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
=== TEST 1: internal platform lists all groups and optionally filters current tenant grants
--- test_code
local status,body=a.request("GET","/api/v1/admin/group/list")
assert(status==200 and #body.data==2)
assert(body.data[1].group_id==1 and body.data[1].has_links==false)
a.create()
status,body=a.request("GET","/api/v1/admin/group/list")
assert(status==200 and body.data[1].has_links==true and body.data[2].has_links==false)
status,body=a.request("GET","/api/v1/admin/group/list?tenant_id=1")
assert(status==200 and #body.data==1 and body.data[1].group_id==1)
assert(a.request("GET","/api/v1/admin/group/list?tenant_id=bad")==400)
local raw
status,body,_,raw=a.request("GET","/api/v1/admin/group/list?tenant_id=999")
assert(status==200 and #body.data==0 and raw:find('"data":[]',1,true))
status,body,_,raw=a.request("GET","/api/v1/admin/group_config/list?group_id=1")
assert(status==200 and raw:find('"data":[]',1,true))
status,body,_,raw=a.request("POST","/api/v1/admin/tenant/create",'{"name":"empty-grants"}')
assert(status==200 and raw:find('"group_ids":[]',1,true))
local tenant_id=body.data.id
status,body,_,raw=a.request("GET","/api/v1/admin/tenant/list")
assert(status==200 and raw:find('"group_ids":[]',1,true))
status,body,_,raw=a.request("PUT","/api/v1/admin/tenant/grant",require("cjson").encode({id=tenant_id,group_ids={}}))
assert(status==200 and raw:find('"group_ids":[]',1,true))
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 2: credential listing includes disabled credentials without plaintext or encrypted secrets
--- test_code
local status,body,_,raw=a.request("GET","/api/v1/admin/credential/list?tenant_id=1",nil,{no_auth=true})
assert(status==200 and #body.data==1 and body.data[1].access_key==a.ak)
assert(body.data[1].tenant_id==1 and body.data[1].status==1)
assert(not raw:find("secret_key",1,true) and not raw:find(a.sk,1,true))
assert(a.request("PUT","/api/v1/admin/credential/disable",require("cjson").encode({access_key=a.ak}))==200)
status,body=a.request("GET","/api/v1/admin/credential/list?tenant_id=1",nil,{no_auth=true})
assert(status==200 and #body.data==1 and body.data[1].status==2 and body.data[1].disabled_at)
assert(body.data[1].secret_key==nil and body.data[1].secret_key_enc==nil)
status,body,_,raw=a.request("GET","/api/v1/admin/credential/list?tenant_id=999",nil,{no_auth=true})
assert(status==200 and raw:find('"data":[]',1,true))
assert(a.request("GET","/api/v1/admin/credential/list")==400)
assert(a.request("GET","/api/v1/admin/credential/list?tenant_id=0")==400)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 3: tenant link list applies current grants and optional group filter, including terminal links
--- test_code
local first=a.create()
local second=a.create({group_id=2,target_url="https://example.com/other"},{ak="other-ak"})
local status,body=a.request("GET","/api/v1/shorten/list")
assert(status==200 and #body.data==1 and body.data[1].code==first and body.data[1].domain=="s.example.com")
status,body=a.request("GET","/api/v1/shorten/list?group_id=1")
assert(status==200 and #body.data==1 and body.data[1].group_id==1)
local raw
status,body,_,raw=a.request("GET","/api/v1/shorten/list?group_id=2")
assert(status==200 and #body.data==0 and raw:find('"data":[]',1,true))
assert(a.request("GET","/api/v1/shorten/list",nil,{no_auth=true})==401)
assert(a.request("GET","/api/v1/shorten/list?group_id=0")==400)
assert(a.request("GET","/api/v1/shorten/list?group_id=4294967296")==400)
assert(a.request("PUT","/api/v1/admin/tenant/grant",'{"id":1,"group_ids":[1,2]}')==200)
status,body=a.request("GET","/api/v1/shorten/list?group_id=2")
assert(status==200 and #body.data==1 and body.data[1].code==second)
assert(a.request("PUT","/api/v1/admin/tenant/grant",'{"id":1,"group_ids":[1]}')==200)
status,body=a.request("GET","/api/v1/shorten/list?group_id=2")
assert(status==200 and #body.data==0)
assert(a.request("PUT","/api/v1/shorten/disable",require("cjson").encode({code=first}))==200)
status,body=a.request("GET","/api/v1/shorten/list")
assert(status==200 and #body.data==1 and body.data[1].status==2)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 4: tenant status and grant changes after authentication are rechecked by the list statement
--- test_code
local code=a.create()
local credentials=a.deps.credential_model
local original=credentials.find_by_access_key
credentials.find_by_access_key=function(...)
    local row,err=original(...)
    assert(a.deps.tenant_model:grant(1,{}))
    return row,err
end
local status,body=a.request("GET","/api/v1/shorten/list")
assert(status==200 and #body.data==0)
credentials.find_by_access_key=original
assert(a.deps.tenant_model:grant(1,{1}))
credentials.find_by_access_key=function(...)
    local row,err=original(...)
    assert(a.deps.tenant_model:set_status(1,2))
    return row,err
end
status,body=a.request("GET","/api/v1/shorten/list")
assert(status==200 and #body.data==0)
credentials.find_by_access_key=original
assert(a.request("GET","/"..code)==302)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 5: the new lists stay bounded to 100 rows with deterministic ordering
--- test_code
assert(a.deps.db:query([[INSERT INTO sl_short_link(code,target_url,group_id)
    SELECT 'listCode'||n::text,'https://example.com/'||n::text,1 FROM generate_series(1,105) n]]))
assert(a.deps.db:query([[INSERT INTO sl_group(group_id,name,domain_entry_id)
    SELECT n,'list-group-'||n::text,1 FROM generate_series(3,107) n]]))
assert(a.deps.db:query([[INSERT INTO sl_tenant_credential(tenant_id,access_key,secret_key_enc)
    SELECT 1,'list-ak-'||n::text,'never-decrypted-fixture' FROM generate_series(1,105) n]]))
local status,body=a.request("GET","/api/v1/shorten/list")
assert(status==200 and #body.data==100 and body.data[1].code=="listCode105")
status,body=a.request("GET","/api/v1/admin/group/list")
assert(status==200 and #body.data==100 and body.data[1].group_id==1 and body.data[100].group_id==100)
status,body=a.request("GET","/api/v1/admin/credential/list?tenant_id=1")
assert(status==200 and #body.data==100 and body.data[1].access_key=="list-ak-105")
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]
