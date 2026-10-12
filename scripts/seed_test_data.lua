-- Explicit local-development fixture; never resets the short-code ID sequence.
-- Run with: resty -I /app/src /app/scripts/seed_test_data.lua
assert(os.getenv("LINKLET_ALLOW_TEST_SEED") == "1", "set LINKLET_ALLOW_TEST_SEED=1 for a disposable development database")
local db = require("lib.database").new({
    host=os.getenv("PGHOST"), port=tonumber(os.getenv("PGPORT")) or 5432,
    database=os.getenv("PGDATABASE"), user=os.getenv("PGUSER"), password=os.getenv("PGPASSWORD"),
})
require("lib.crypto").configure(os.getenv("LINKLET_ENCRYPTION_KEY"))
local file = assert(io.open("/app/migrations/002_seed_test_data.sql","r"))
local sql = file:read("*a")
file:close()
assert(db:query(sql))
local ciphertext = assert(require("lib.crypto").encrypt("test-secret-key-001"))
assert(db:query([[INSERT INTO sl_tenant_credential(tenant_id,access_key,secret_key_enc,status)
    VALUES (1,$1,$2,1) ON CONFLICT(access_key) DO NOTHING]],"test-access-key-001",ciphertext))
print("Development fixture prepared; existing credentials and sequence remain unchanged")
