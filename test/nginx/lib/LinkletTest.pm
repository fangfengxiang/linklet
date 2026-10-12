package LinkletTest;
use strict;
use warnings;
use Cwd qw(abs_path);
use Test::Nginx::Socket::Lua;
sub import {
    $ENV{LINKLET_ROOT} = abs_path('.');
    $ENV{TEST_NGINX_BINARY} ||= 'openresty';
    $ENV{TEST_NGINX_SERVROOT} ||= "$ENV{LINKLET_ROOT}/.test-nginx";
    Test::Nginx::Socket::Lua::add_block_preprocessor(sub {
        my $block = shift;
        my $root = $ENV{LINKLET_ROOT};
        $block->set_value('main_config', 'env LINKLET_MULTI_A; env LINKLET_MULTI_B; env LINKLET_TEST_PGPORT; env PGHOST; env PGPORT; env PGDATABASE; env PGUSER; env PGPASSWORD; env LINKLET_ENCRYPTION_KEY;' . ($block->main_config || ''));

        my $coverage = '';
        my $worker = 'if rawget(_G,"linklet_production_test") then require("app").init_worker() end';
        if ($ENV{LINKLET_COVERAGE}) {
            $worker = qq{assert(ngx.timer.at(0,function() require("coverage").start("$root") end));} . $worker;
            $coverage = qq{exit_worker_by_lua_block { require("coverage").stop("$root") }};
        }
        $coverage .= qq{init_worker_by_lua_block { $worker }};
        $block->set_value('http_config', qq{
            lua_package_path "$root/src/?.lua;$root/test/nginx/?.lua;$root/.test-deps/lua/?.lua;$root/.test-deps/lua/?/init.lua;$root/.test-deps/runtime/share/lua/5.1/?.lua;$root/.test-deps/runtime/share/lua/5.1/?/init.lua;;";
            lua_package_cpath "$root/.test-deps/runtime/lib/lua/5.1/?.so;;";
            lua_shared_dict linklet_cache 10m;
            lua_shared_dict linklet_locks 1m;
            lua_shared_dict other_cache 1m;
        } . $coverage . ($block->http_config || ''));
    });
}
1;
