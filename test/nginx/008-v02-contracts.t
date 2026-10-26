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
=== TEST 1: shared group grants apply to create/query/disable and revocation blocks management
--- test_code
local json=require("cjson")
assert(a.request("PUT","/api/v1/admin/tenant/grant",'{"id":2,"group_ids":[1,1,2]}')==200)
local code=a.create(nil,{ak="other-ak"})
assert(a.request("GET","/api/v1/shorten/get?code="..code)==200)
assert(a.request("PUT","/api/v1/shorten/disable",json.encode({code=code}))==200)
code=a.create()
assert(a.request("PUT","/api/v1/admin/tenant/grant",'{"id":2,"group_ids":[2]}')==200)
assert(a.request("GET","/api/v1/shorten/get?code="..code,nil,{ak="other-ak"})==404)
assert(a.request("PUT","/api/v1/shorten/disable",json.encode({code=code}),{ak="other-ak"})==404)
assert(a.request("POST","/api/v1/shorten/create",'{"group_id":1,"target_url":"https://example.com"}',{ak="other-ak"})==403)
assert(a.request("PUT","/api/v1/admin/tenant/grant",'{"id":2,"group_ids":[999]}')==409)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 2: Host+Code cache isolation; disabled tenant and group do not invalidate a permanent link
--- test_code
local code=a.create({group_id=1,target_url="https://example.com/permanent",expires_at=ngx.null})
assert(a.request("GET","/"..code)==302)
assert(a.request("GET","/"..code,nil,{request_host="other.example.com"})==404)
assert(a.request("PUT","/api/v1/admin/tenant/status",'{"id":1,"status":2}')==200)
assert(a.request("PUT","/api/v1/admin/group/configure",'{"group_id":1,"status":2}')==200)
assert(a.deps.cache:invalidate(code))
assert(a.request("GET","/"..code)==302)
assert(a.request("POST","/api/v1/shorten/create",'{"group_id":1,"target_url":"https://example.com"}')==401)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 3: issued links freeze binding, including disabled and expired links
--- test_code
local code=a.create()
assert(a.request("GET","/"..code)==302)
assert(a.request("PUT","/api/v1/admin/group/configure",'{"group_id":1,"domain_entry_id":2}')==409)
assert(a.request("PUT","/api/v1/admin/group/configure",'{"group_id":1,"domain_entry_id":1,"status":2}')==200)
assert(a.request("GET","/"..code)==302)
assert(a.request("GET","/"..code,nil,{request_host="other.example.com"})==404)
assert(a.deps.link_model:disable(code,1))
assert(a.deps.db:query("UPDATE sl_short_link SET expires_at=NOW()-INTERVAL '1 day' WHERE code=$1",code))
assert(not a.deps.db:query("UPDATE sl_group SET domain_entry_id=2 WHERE group_id=1"))
assert(not a.deps.db:query("UPDATE sl_group SET deleted_at=NOW() WHERE group_id=1"))
assert(a.request("PUT","/api/v1/admin/domain/disable",'{"id":1}')==409)
assert(not a.deps.db:query("UPDATE sl_domain_entry SET deleted_at=NOW() WHERE id=1"))
-- An empty group may rebind; its released domain may then go offline.
assert(a.request("PUT","/api/v1/admin/group/configure",'{"group_id":2,"domain_entry_id":1}')==200)
assert(a.request("PUT","/api/v1/admin/domain/disable",'{"id":2}')==200)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 4: operator APIs manage domain lifecycle, groups and configuration without exposing credentials
--- test_code
local status,body=a.request("POST","/api/v1/admin/domain/create",'{"domain":"new.example.com","tag":"test"}')
assert(status==200 and body.data.status==1)
local id=body.data.id
local json=require("cjson")
assert(a.request("PUT","/api/v1/admin/domain/deploy",json.encode({id=id}))==200)
assert(a.request("POST","/api/v1/admin/group/create",json.encode({group_id=100,name="shared",domain_entry_id=id}))==200)
assert(a.request("PUT","/api/v1/admin/group_config/set",'{"group_id":100,"config_key":"future_policy","config_value":"off"}')==200)
assert(a.request("GET","/api/v1/admin/group_config/list?group_id=100")==200)
assert(a.request("DELETE","/api/v1/admin/group_config/delete",'{"group_id":100,"config_key":"future_policy"}')==200)
assert(a.request("GET","/api/v1/admin/domain/list")==200)
assert(a.request("GET","/api/v1/admin/group/list?tenant_id=1")==200)
assert(a.request("PUT","/api/v1/admin/domain/deploy",json.encode({id=id}))==409)
assert(a.request("POST","/api/v1/admin/domain/create",'{"domain":"https://bad.example.com"}')==400)
assert(a.request("PUT","/api/v1/admin/group/configure",'{"group_id":1,"domain_entry_id":false}')==400)
assert(a.request("PUT","/api/v1/admin/tenant/grant",'{"id":1,"group_ids":[false]}')==400)
assert(a.request("PUT","/api/v1/admin/group_config/set",'{"group_id":100,"config_key":"x","config_value":false}')==400)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 5: domain offline serializes with a concurrent group binding
--- test_code
local domain=assert(a.deps.domain_entry_model:create("race.example.com"))
assert(a.deps.domain_entry_model:deploy(domain.id))
local locked=require("ngx.semaphore").new()
local resume=require("ngx.semaphore").new()
local offline=ngx.thread.spawn(function()
    return a.deps.db:transaction(function(conn)
        assert(conn:query("UPDATE sl_domain_entry SET status=3 WHERE id=$1",domain.id))
        locked:post(1);assert(resume:wait(5));return true
    end)
end)
assert(locked:wait(5))
local bound=ngx.thread.spawn(function() return a.deps.group_model:configure(1,domain.id) end)
ngx.sleep(0.05);resume:post(1)
local ok,result=ngx.thread.wait(offline);assert(ok and result)
local ran,row,err=ngx.thread.wait(bound);assert(ran and not row and err)
assert(a.deps.group_model:find_by_id(1).domain_entry_id==1)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 6: mixed bulk IDs and explicit segments do not overlap; sequence cannot rewind
--- test_code
local generator=require("linklet.id.generator")
assert(a.deps.db:query("UPDATE sl_id_sequence SET step=3 WHERE sequence_key=1"))
local gen=generator.new({allocator=a.deps.runtime})
assert(gen:next_id()==1)
local t1=ngx.thread.spawn(function() return gen:next_ids(25) end)
local t2=ngx.thread.spawn(function() return gen:allocate_segment(10) end)
local ok,ids=ngx.thread.wait(t1);assert(ok and #ids==25)
local ok2,segment=ngx.thread.wait(t2);assert(ok2 and segment)
local seen={[1]=true}
for _,id in ipairs(ids) do assert(not seen[id]);seen[id]=true end
for id=segment.start,segment["end"] do assert(not seen[id]);seen[id]=true end
assert(not a.deps.db:query("UPDATE sl_id_sequence SET current_max=0 WHERE sequence_key=1"))
assert(not a.deps.db:query("DELETE FROM sl_id_sequence WHERE sequence_key=1"))
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 7: malformed expiration rejected in both create and gen; immutable credentials cannot be reused
--- test_code
for _,action in ipairs({"create","gen"}) do
    for _,expiry in ipairs({"bad","2025-02-29T00:00:00Z","2001-01-01T00:00:00Z"}) do
        assert(a.request("POST","/api/v1/shorten/"..action,require("cjson").encode({group_id=1,target_url="https://example.com",expires_at=expiry}))==400)
    end
end
assert(not a.deps.db:query("UPDATE sl_tenant_credential SET secret_key_enc='changed' WHERE access_key=$1",a.ak))
assert(not a.deps.db:query("DELETE FROM sl_tenant_credential WHERE access_key=$1",a.ak))
assert(a.request("GET","/api/v1/shorten/get")==400)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 8: committed link creation blocks a concurrent rebind at the database boundary
--- test_code
local locked=require("ngx.semaphore").new()
local resume=require("ngx.semaphore").new()
local creator=ngx.thread.spawn(function()
    return a.deps.db:transaction(function(conn)
        assert(conn:query("INSERT INTO sl_short_link(code,target_url,group_id) VALUES('raceCode','https://example.com',1)"))
        locked:post(1);assert(resume:wait(5));return true
    end)
end)
assert(locked:wait(5))
local binder=ngx.thread.spawn(function() return a.deps.group_model:configure(1,2) end)
ngx.sleep(0.05);resume:post(1)
local ok,committed=ngx.thread.wait(creator);assert(ok and committed)
local ran,row,err=ngx.thread.wait(binder);assert(ran and not row and err=="group_domain_locked")
assert(a.deps.group_model:find_by_id(1).domain_entry_id==1)
assert(a.request("GET","/raceCode")==302)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 9: a rebind racing gen returns the domain confirmed by the insert transaction
--- test_code
local locked=require("ngx.semaphore").new()
local resume=require("ngx.semaphore").new()
local binder=ngx.thread.spawn(function()
    return a.deps.db:transaction(function(conn)
        assert(conn:query("UPDATE sl_group SET domain_entry_id=2 WHERE group_id=1"))
        locked:post(1);assert(resume:wait(5));return true
    end)
end)
assert(locked:wait(5))
local creator=ngx.thread.spawn(function()
    return a.request("POST","/api/v1/shorten/gen",'{"group_id":1,"target_url":"https://example.com"}')
end)
ngx.sleep(0.05);resume:post(1)
local ok,committed=ngx.thread.wait(binder);assert(ok and committed)
local ran,status,body=ngx.thread.wait(creator)
assert(ran and status==200 and body.data.short_url=="https://other.example.com/"..body.data.code)
assert(a.request("GET","/"..body.data.code)==404)
assert(a.request("GET","/"..body.data.code,nil,{request_host="other.example.com"})==302)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 10: concurrent SLDS creations keep each transaction domain view local to its call
--- test_code
local threads={}
for index=1,8 do
    local group_id=index%2+1
    threads[index]=ngx.thread.spawn(function()
        local status,body=a.request("POST","/api/v1/shorten/gen",require("cjson").encode({
            group_id=group_id,target_url="https://example.com/concurrent-view"}),
            {ak=group_id==1 and a.ak or "other-ak"})
        assert(status==200)
        local domain=group_id==1 and "s.example.com" or "other.example.com"
        assert(body.data.short_url=="https://"..domain.."/"..body.data.code)
        return body.data.code
    end)
end
local seen={}
for _,thread in ipairs(threads) do
    local ok,code=ngx.thread.wait(thread)
    assert(ok and not seen[code]);seen[code]=true
end
--- request
GET /t
--- timeout: 15
--- response_body
accepted
--- no_error_log
[error]
