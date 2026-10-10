-- migrations/002_seed_test_data.sql
-- E2E 测试种子数据 / E2E test seed data
-- 创建测试租户、域名、场景、凭证 / Create test tenant, domain, scene, credential

BEGIN;

-- 测试租户 / Test tenant
INSERT INTO sl_tenant (id, name, status)
VALUES (1, 'E2E Test Tenant', 1)
ON CONFLICT (id) DO NOTHING;

-- 测试域名入口 / Test domain entry
INSERT INTO sl_domain_entry (id, tenant_id, domain, label, status)
VALUES (1, 1, 's.test.local', 'e2e-test', 1)
ON CONFLICT (id) DO NOTHING;

-- 测试场景 / Test scene
INSERT INTO sl_scene (scene_id, tenant_id, name, domain_entry_id, status)
VALUES (1, 1, 'E2E Test Scene', 1, 1)
ON CONFLICT (scene_id) DO NOTHING;

-- 测试凭证 / Test credential
-- AK: test-access-key-001
-- SK: test-secret-key-001
-- SK 加密后存储（XOR + Base64，加密密钥: linklet-default-key-change-me）
-- 以下 SK 密文通过 Lua 在 Docker 容器内生成，这里用预计算值
-- 实际 E2E 测试中通过 API 直接注入或在容器启动时生成
INSERT INTO sl_tenant_credential (tenant_id, access_key, secret_key_enc, status)
VALUES (1, 'test-access-key-001', 'SEED_PLACEHOLDER', 1)
ON CONFLICT (access_key) DO NOTHING;

-- 直接插入一条已知短链用于解析测试 / Insert a known link for resolution test
INSERT INTO sl_link (id, code, target_url, scene_id, status)
VALUES (1001, 'e2eTest', 'https://github.com/openresty/openresty', 1, 1)
ON CONFLICT (code) DO NOTHING;

COMMIT;
