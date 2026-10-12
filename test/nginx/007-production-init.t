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
    $init =~ s/local app = require\("app"\)/linklet_production_test = true; local app = require("app")/;
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
        local deps = require("app").get_deps()
        assert(deps.db.config.host == "127.0.0.1")
        assert(deps.db.config.port == tonumber(os.getenv("LINKLET_TEST_PGPORT")))
        assert(deps.db.config.database == "linklet_test")
        assert(deps.db.config.password == "acceptance_only")
        assert(require("lib.crypto").decrypt(assert(require("lib.crypto").encrypt("round-trip"))) == "round-trip")
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
