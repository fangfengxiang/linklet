-- migrations/002_seed_test_data.sql
-- E2E 测试种子数据 / E2E test seed data
-- 创建测试租户、域名、分组、凭证 / Create test tenant, domain, group, credential

BEGIN;

-- 测试租户 / Test tenant
INSERT INTO sl_tenant (id, name, status)
VALUES (1, 'E2E Test Tenant', 1)
ON CONFLICT (id) DO NOTHING;

-- 测试域名入口 / Test domain entry
INSERT INTO sl_domain_entry (id, domain, tag, status)
VALUES (1, 's.test.local', 'e2e-test', 2)
ON CONFLICT (id) DO NOTHING;

-- 测试分组 / Test group
INSERT INTO sl_group (group_id, name, domain_entry_id, status)
VALUES (1, 'E2E Test Group', 1, 1)
ON CONFLICT (group_id) DO NOTHING;
UPDATE sl_tenant SET group_ids=ARRAY[1]::bigint[] WHERE id=1;

-- Credentials are created by scripts/seed_test_data.lua using the configured AES-GCM key.

-- 直接插入一条已知短链用于解析测试 / Insert a known link for resolution test
INSERT INTO sl_short_link (id, code, target_url, group_id, status)
VALUES (1001, 'e2eTest', 'https://github.com/openresty/openresty', 1, 1)
ON CONFLICT (code) DO NOTHING;

SELECT setval('sl_tenant_id_seq', (SELECT MAX(id) FROM sl_tenant));
SELECT setval('sl_domain_entry_id_seq', (SELECT MAX(id) FROM sl_domain_entry));
SELECT setval('sl_group_group_id_seq', (SELECT MAX(group_id) FROM sl_group));
SELECT setval('sl_link_id_seq', (SELECT MAX(id) FROM sl_short_link));
COMMIT;
