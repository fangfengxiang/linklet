-- migrations/002_seed_test_data.sql
-- E2E 测试种子数据 / E2E test seed data
-- 创建测试租户、域名、场景、凭证 / Create test tenant, domain, scene, credential

BEGIN;

-- 测试租户 / Test tenant
INSERT INTO sl_tenant (id, name, status)
VALUES (1, 'E2E Test Tenant', 1)
ON CONFLICT (id) DO NOTHING;

-- 测试域名入口 / Test domain entry
INSERT INTO sl_domain_entry (id, domain, tag, status)
VALUES (1, 's.test.local', 'e2e-test', 2)
ON CONFLICT (id) DO NOTHING;

-- 测试场景 / Test scene
INSERT INTO sl_scene (scene_id, name, domain_entry_id, status)
VALUES (1, 'E2E Test Scene', 1, 1)
ON CONFLICT (scene_id) DO NOTHING;
UPDATE sl_tenant SET scene_ids=ARRAY[1]::bigint[] WHERE id=1;

-- Credentials are created by scripts/seed_test_data.lua using the configured AES-GCM key.

-- 直接插入一条已知短链用于解析测试 / Insert a known link for resolution test
INSERT INTO sl_short_link (id, code, target_url, scene_id, status)
VALUES (1001, 'e2eTest', 'https://github.com/openresty/openresty', 1, 1)
ON CONFLICT (code) DO NOTHING;

SELECT setval('sl_tenant_id_seq', (SELECT MAX(id) FROM sl_tenant));
SELECT setval('sl_domain_entry_id_seq', (SELECT MAX(id) FROM sl_domain_entry));
SELECT setval('sl_scene_scene_id_seq', (SELECT MAX(scene_id) FROM sl_scene));
SELECT setval('sl_link_id_seq', (SELECT MAX(id) FROM sl_link));
COMMIT;
