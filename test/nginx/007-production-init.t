use Test::Nginx::Socket::Lua 'no_plan';
use lib 'test/nginx/lib';
use LinkletTest;
repeat_each(1);
no_shuffle();
add_block_preprocessor(sub {
    my $block = shift;
    open my $file, '<', 'conf/nginx.conf' or die $!;
    local $/;
    my $production = <$file>;
    my ($init) = $production =~ /(    init_by_lua_block \{.*?\n    \})/s;
    die 'Production initialization missing' unless $init;
    $init =~ s/local app = require\("linklet.app"\)/linklet_production_test = true; local app = require("linklet.app")/;
    my $http = ($block->http_config || '') . $init;
    $block->set_value('http_config',$http);
    $block->set_value('config', 'include ' . $ENV{LINKLET_ROOT} . '/conf/locations.conf;' . $block->config);
});
run_tests();
__DATA__
=== TEST 1: production init retains deployment environment and starts real cache synchronization
--- config
location /t {
    content_by_lua_block {
        local deps = require("linklet.app").get_deps()
        assert(deps.db.config.host == "127.0.0.1")
        assert(deps.db.config.port == tonumber(os.getenv("LINKLET_TEST_PGPORT")))
        assert(deps.db.config.database == "linklet_test")
        assert(deps.db.config.password == "acceptance_only")
        assert(require("linklet.crypto").decrypt(assert(require("linklet.crypto").encrypt("round-trip"))) == "round-trip")
        ngx.sleep(0.6)
        assert(ngx.shared.linklet_cache:get("cache:checked"))
        ngx.say("initialized")
    }
}
--- request
GET /t
--- response_body
initialized
--- no_error_log
[error]

=== TEST 2: Gateway role starts without credential configuration and does not expose Admin
--- config
location /t {
    content_by_lua_block {
        local a=require("acceptance")
        a.setup()
        local code=a.create()
        local app=require("linklet.app")
        local gateway=app.init({role="gateway",database=a.deps.db.config,encryption_key="unused-invalid-key"})
        gateway.cache.sync_window=nil
        assert(gateway.role=="gateway" and gateway.auth==nil and gateway.credential_model==nil)
        assert(gateway.id_generator==nil and app.get_router()==nil)
        assert(a.request("GET","/"..code)==302)
        assert(a.request("POST","/api/v1/shorten/create",'{"group_id":1,"target_url":"https://example.com"}')==404)
        assert(a.request("GET","/health")==200)
        ngx.say("gateway role accepted")
    }
}
--- request
GET /t
--- response_body
gateway role accepted
--- no_error_log
[error]

=== TEST 3: Admin role builds only its entry and the Gateway bypasses the Admin router
--- config
location /t {
    content_by_lua_block {
        local a=require("acceptance")
        a.setup()
        local code=a.create()
        local app=require("linklet.app")
        assert(not app.get_router():match("GET","/"..code))
        local original=app.get_router().dispatch
        app.get_router().dispatch=function() error("Gateway must not enter Admin router") end
        assert(a.request("GET","/"..code)==302)
        app.get_router().dispatch=original
        local admin=app.init({role="admin",database=a.deps.db.config,encryption_key=string.rep("ab",32)})
        assert(admin.role=="admin" and admin.resolver==nil and app.get_router())
        assert(a.request("GET","/"..code)==404)
        assert(a.request("GET","/api/v1/admin/tenant/list")==200)
        ngx.say("admin role accepted")
    }
}
--- request
GET /t
--- response_body
admin role accepted
--- no_error_log
[error]
