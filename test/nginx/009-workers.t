BEGIN { $ENV{TEST_NGINX_REUSE_PORT} = 1; }
use Test::Nginx::Socket::Lua 'no_plan';
use lib 'test/nginx/lib';
use LinkletTest;
repeat_each(1);
workers(2);
master_process_enabled(1);
add_block_preprocessor(sub {
    my $block=shift;
    my $config=$block->config;
    $config =~ s/__ROOT__/$ENV{LINKLET_ROOT}/g;
    $block->set_value('config',$config);
});
run_tests();
__DATA__
=== TEST 1: disabling a warmed link invalidates redirects in both real worker processes
--- http_config
init_by_lua_block {
    linklet_production_test=true
    local app=require("linklet.app")
    app.init({database={host="127.0.0.1",port=tonumber(os.getenv("LINKLET_TEST_PGPORT")),
        database="linklet_test",user="linklet",password="acceptance_only"},
        encryption_key=string.rep("ab",32)})
}
--- config
include __ROOT__/conf/locations.conf;
header_filter_by_lua_block { ngx.header["X-Test-Worker"]=ngx.worker.pid() }
location = /t {
    content_by_lua_block {
        local a=require("acceptance")
        a.setup()
        local code=a.create()
        ngx.sleep(0.6)
        assert(ngx.shared.linklet_cache:get("cache:checked"), "production synchronization did not start")
        local function visit(expected)
            local seen={}
            for wave=1,40 do
                local threads={}
                for i=1,8 do
                    threads[i]=ngx.thread.spawn(function() return a.request("GET","/"..code) end)
                end
                for _,thread in ipairs(threads) do
                    local ok,status,_,headers=ngx.thread.wait(thread)
                    assert(ok and status==expected)
                    local pid=assert(headers:match("X%-Test%-Worker: (%d+)"))
                    seen[pid]=true
                end
                local count=0
                for _ in pairs(seen) do count=count+1 end
                if count==2 then return end
                ngx.sleep(0.05)
            end
            error("requests did not reach both workers")
        end
        visit(302)
        assert(a.request("PUT","/api/v1/shorten/disable",require("cjson").encode({code=code}))==200)
        visit(410)
        ngx.say("workers accepted")
    }
}
--- request
GET /t
--- timeout: 15
--- response_body
workers accepted
--- no_error_log
[error]
