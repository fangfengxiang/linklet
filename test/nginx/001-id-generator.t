use Test::Nginx::Socket::Lua 'no_plan';
use lib 'test/nginx/lib';
use LinkletTest;
repeat_each(1);
no_shuffle();
run_tests();
__DATA__
=== TEST 1: adjacent real PostgreSQL segments never overlap
--- config
location /t {
    content_by_lua_block {
        local db = require("linklet.db.postgres").new({host="127.0.0.1",port=tonumber(os.getenv("LINKLET_TEST_PGPORT")) or 15432,database="linklet_test",user="linklet",password="acceptance_only"})
        assert(db:query("TRUNCATE sl_id_sequence"))
        assert(db:query("INSERT INTO sl_id_sequence(sequence_key,current_max) VALUES(1,0)"))
        local gen = require("linklet.id.generator").new({allocator=require("linklet.repository.runtime").new(db),segment_size=2})
        local seen = {}
        for i=1,8 do
            local id = assert(gen:next_id())
            assert(not seen[id], "duplicate ID: " .. id)
            seen[id] = true
        end
        ngx.say("unique")
    }
}
--- request
GET /t
--- response_body
unique
--- no_error_log
[error]

=== TEST 2: concurrent coroutines cannot overwrite a worker segment
--- config
location /t {
    content_by_lua_block {
        local db = require("linklet.db.postgres").new({host="127.0.0.1",port=tonumber(os.getenv("LINKLET_TEST_PGPORT")) or 15432,database="linklet_test",user="linklet",password="acceptance_only"})
        assert(db:query("TRUNCATE sl_id_sequence"))
        assert(db:query("INSERT INTO sl_id_sequence(sequence_key,current_max) VALUES(1,0)"))
        local gen = require("linklet.id.generator").new({allocator=require("linklet.repository.runtime").new(db),segment_size=2})
        local threads, seen = {}, {}
        for i=1,20 do threads[i] = ngx.thread.spawn(function() return assert(gen:next_id()) end) end
        for i=1,20 do
            local ok, id = ngx.thread.wait(threads[i])
            assert(ok, id)
            assert(not seen[id], "duplicate ID: " .. id)
            seen[id] = true
        end
        ngx.say("unique")
    }
}
--- request
GET /t
--- response_body
unique
--- no_error_log
[error]

=== TEST 3: Base62 and bijection remain exact across the 32-bit space
--- config
location /t {
    content_by_lua_block {
        local o = require("linklet.id.obfuscator")
        for _, id in ipairs({0,1,4194304,100000000,2147483647,4294967295}) do
            local code = o.generate(id)
            assert(#code >= 6 and o.reverse(code) == id)
        end
        assert(not pcall(o.generate,4294967296))
        assert(not pcall(o.generate,1.5))
        ngx.say("exact")
    }
}
--- request
GET /t
--- response_body
exact
--- no_error_log
[error]

=== TEST 4: ID space exhaustion fails explicitly instead of wrapping
--- config
location /t {
    content_by_lua_block {
        local db = require("linklet.db.postgres").new({host="127.0.0.1",port=tonumber(os.getenv("LINKLET_TEST_PGPORT")) or 15432,database="linklet_test",user="linklet",password="acceptance_only"})
        assert(db:query("UPDATE sl_id_sequence SET current_max = 4294967294 WHERE id=1"))
        local last = require("linklet.id.generator").new({allocator=require("linklet.repository.runtime").new(db),segment_size=1})
        assert(last:next_id() == 4294967295)
        local id,err = last:next_id()
        assert(not id and err:find("exhausted"))
        assert(not db:query("UPDATE sl_id_sequence SET current_max = 4294967296 WHERE id=1"))
        ngx.say("bounded")
    }
}
--- request
GET /t
--- response_body
bounded
--- no_error_log
[error]
