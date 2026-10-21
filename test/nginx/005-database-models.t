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
=== TEST 1: pooled PostgreSQL connections are reused, SQL values stay literal
--- test_code
local db = a.deps.db
local rows,err=db:query("SELECT 1")
assert(rows and err==nil, "success metadata must not be reported as an error")
local first = assert(db:query("SELECT pg_backend_pid() AS pid"))[1].pid
local second = assert(db:query("SELECT pg_backend_pid() AS pid"))[1].pid
assert(first == second)
local text = "x'; DROP TABLE sl_short_link; --"
assert(db:query("SELECT $1::text AS value",text)[1].value == text)
local rows = assert(db:query("SELECT $1::text AS a, $2::boolean AS b, $3::int AS c",nil,false,42))
assert((rows[1].a == nil or rows[1].a == ngx.null) and rows[1].b == false and tonumber(rows[1].c) == 42)
assert(not db:query("SELECT $1",{}))
assert(db:query("SELECT 1"))
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 2: transactions roll back nil/error and thrown exceptions; successful work commits
--- test_code
local db = a.deps.db
local result, err = db:transaction(function(conn)
    assert(conn:query("INSERT INTO sl_tenant(name) VALUES ('rollback-nil')"))
    return nil,"expected failure"
end)
assert(not result and err == "expected failure")
assert(not db:transaction(function(conn)
    assert(conn:query("INSERT INTO sl_tenant(name) VALUES ('rollback-thrown')"))
    error("expected exception")
end))
assert(db:transaction(function(conn)
    assert(conn:query("INSERT INTO sl_tenant(name) VALUES ('committed')"))
    return true
end))
assert(db:query("SELECT COUNT(*) AS count FROM sl_tenant WHERE name LIKE 'rollback-%'")[1].count == 0)
assert(db:query("SELECT COUNT(*) AS count FROM sl_tenant WHERE name = 'committed'")[1].count == 1)
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]

=== TEST 3: database enforces group binding, immutable domain, terminal states and permanent short codes
--- test_code
local db = a.deps.db
assert(db:query("INSERT INTO sl_group(group_id,name,domain_entry_id) VALUES (300,'shared-domain',2)"))
assert(not db:query("UPDATE sl_domain_entry SET domain = 'changed.example.com' WHERE id=1"))
local code = a.create()
assert(not db:query("UPDATE sl_short_link SET status=9 WHERE code=$1",code))
assert(a.deps.link_model:disable(code,1))
assert(not db:query("UPDATE sl_short_link SET status=1 WHERE code=$1",code))
assert(not db:query("DELETE FROM sl_short_link WHERE code=$1",code))
assert(not a.deps.link_model:create({code=code,target_url="https://example.com",group_id=1}))
assert(not a.deps.domain_entry_model:disable(1))
assert(not db:query("UPDATE sl_short_link SET code='changed' WHERE code=$1",code))
assert(not db:query("UPDATE sl_short_link SET target_url='https://changed.example.com' WHERE code=$1",code))
assert(not db:query("UPDATE sl_short_link SET group_id=2 WHERE code=$1",code))
assert(not db:query("UPDATE sl_group SET domain_entry_id=2 WHERE group_id=1"))
assert(not a.deps.domain_entry_model:disable(1))
assert(not db:query("UPDATE sl_domain_entry SET status=1 WHERE id=1"))
--- request
GET /t
--- response_body
accepted
--- no_error_log
[error]
