-- scripts/seed_test_data.lua
-- E2E 测试种子数据生成 / E2E test seed data generation
-- 在 OpenResty 容器内运行 / Run inside OpenResty container
-- 用法: lua /app/scripts/seed_test_data.lua

-- 设置 Lua 路径 / Set Lua path
package.path = "/app/src/?.lua;/app/src/?/init.lua;;" .. package.path

local Database = require("lib.database")
local TenantModel = require("models.tenant")
local DomainEntryModel = require("models.domain_entry")
local SceneModel = require("models.scene")
local TenantCredential = require("models.tenant_credential")
local LinkModel = require("models.link")
local IdGenerator = require("lib.id_generator")
local Obfuscator = require("lib.obfuscator")

-- 数据库配置 / Database config
local db = Database.new({
    host = os.getenv("PGHOST") or "127.0.0.1",
    port = tonumber(os.getenv("PGPORT") or "5432"),
    database = os.getenv("PGDATABASE") or "linklet",
    user = os.getenv("PGUSER") or "linklet",
    password = os.getenv("PGPASSWORD") or "",
})

-- 测试数据 / Test data
local TEST_TENANT_ID = 1
local TEST_DOMAIN_ID = 1
local TEST_SCENE_ID = 1
local TEST_AK = "test-access-key-001"
local TEST_SK = "test-secret-key-001"

-- 1. 创建租户 / Create tenant
local res, err = db:query([[
    INSERT INTO sl_tenant (id, name, status)
    VALUES (1, 'E2E Test Tenant', 1)
    ON CONFLICT (id) DO NOTHING
]])
if not res then print("WARN tenant: " .. tostring(err)) end

-- 2. 创建域名入口 / Create domain entry
res, err = db:query([[
    INSERT INTO sl_domain_entry (id, tenant_id, domain, label, status)
    VALUES (1, 1, 's.test.local', 'e2e-test', 1)
    ON CONFLICT (id) DO NOTHING
]])
if not res then print("WARN domain: " .. tostring(err)) end

-- 3. 创建场景 / Create scene
res, err = db:query([[
    INSERT INTO sl_scene (scene_id, tenant_id, name, domain_entry_id, status)
    VALUES (1, 1, 'E2E Test Scene', 1, 1)
    ON CONFLICT (scene_id) DO NOTHING
]])
if not res then print("WARN scene: " .. tostring(err)) end

-- 4. 创建凭证（使用 Lua 加密 SK）/ Create credential with encrypted SK
local cred_model = TenantCredential.new(db)
-- 先删除旧数据 / Delete old credential first
db:query("DELETE FROM sl_tenant_credential WHERE access_key = $1", TEST_AK)
local cred, cerr = cred_model:create(TEST_TENANT_ID, TEST_AK, TEST_SK)
if not cred then
    print("ERROR credential: " .. tostring(cerr))
    os.exit(1)
end
print("OK credential created: AK=" .. TEST_AK .. ", SK=" .. TEST_SK)

-- 5. 插入已知短链用于解析测试 / Insert known link for resolution test
local link_model = LinkModel.new(db)
db:query("DELETE FROM sl_link WHERE code = 'e2eTest'")
local link, lerr = link_model:create({
    code = "e2eTest",
    target_url = "https://github.com/openresty/openresty",
    scene_id = TEST_SCENE_ID,
})
if not link then
    print("WARN link: " .. tostring(lerr))
else
    print("OK link created: code=e2eTest -> https://github.com/openresty/openresty")
end

-- 6. 重置发号器序列 / Reset ID sequence
db:query("UPDATE sl_id_sequence SET current_max = 0 WHERE id = 1")
print("OK ID sequence reset")

print("")
print("========================================")
print("  Seed data complete!")
print("  AK: " .. TEST_AK)
print("  SK: " .. TEST_SK)
print("  Tenant ID: " .. TEST_TENANT_ID)
print("  Scene ID: " .. TEST_SCENE_ID)
print("  Domain: s.test.local")
print("  Known link: e2eTest -> https://github.com/openresty/openresty")
print("========================================")
