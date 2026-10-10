-- migrations/001_init.sql
-- Linklet core schema: 6 tables for multi-tenant short link system
-- Tables: sl_tenant, sl_domain_entry, sl_scene, sl_scene_config, sl_link, sl_id_sequence

BEGIN;

-- 租户表 / Tenant table
CREATE TABLE IF NOT EXISTS sl_tenant (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(255) NOT NULL,
    scene_ids   BIGINT[] DEFAULT '{}',
    status      SMALLINT NOT NULL DEFAULT 1,  -- 1=active, 2=disabled
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 域名入口表 / Domain entry table
CREATE TABLE IF NOT EXISTS sl_domain_entry (
    id          BIGSERIAL PRIMARY KEY,
    tenant_id   BIGINT NOT NULL REFERENCES sl_tenant(id),
    domain      VARCHAR(255) NOT NULL,
    label       VARCHAR(255),
    description TEXT,
    status      SMALLINT NOT NULL DEFAULT 1,  -- 1=active, 2=disabled, 3=deleted
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    enabled_at  TIMESTAMPTZ,
    disabled_at TIMESTAMPTZ,
    deleted_at  TIMESTAMPTZ,
    UNIQUE(domain)
);

-- 场景表 / Scene table
CREATE TABLE IF NOT EXISTS sl_scene (
    scene_id        BIGSERIAL PRIMARY KEY,
    tenant_id       BIGINT NOT NULL REFERENCES sl_tenant(id),
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    domain_entry_id BIGINT REFERENCES sl_domain_entry(id),
    status          SMALLINT NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 场景配置表 / Scene config table
CREATE TABLE IF NOT EXISTS sl_scene_config (
    id          BIGSERIAL PRIMARY KEY,
    scene_id    BIGINT NOT NULL REFERENCES sl_scene(scene_id),
    config_key  VARCHAR(255) NOT NULL,
    config_value TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(scene_id, config_key)
);

-- 短链核心表 / Short link core table
CREATE TABLE IF NOT EXISTS sl_link (
    id          BIGSERIAL PRIMARY KEY,
    code        VARCHAR(20) NOT NULL,
    target_url  TEXT NOT NULL,
    scene_id    BIGINT NOT NULL REFERENCES sl_scene(scene_id),
    status      SMALLINT NOT NULL DEFAULT 1,  -- 1=active, 2=disabled
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ,
    UNIQUE(code)
);

-- 租户凭证表 / Tenant credential table (AK/SK)
CREATE TABLE IF NOT EXISTS sl_tenant_credential (
    id              BIGSERIAL PRIMARY KEY,
    tenant_id       BIGINT NOT NULL REFERENCES sl_tenant(id),
    access_key      VARCHAR(128) NOT NULL,
    secret_key_enc  TEXT NOT NULL,
    status          SMALLINT NOT NULL DEFAULT 1,  -- 1=active, 2=disabled
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(access_key)
);

-- 发号器序列表 / ID generator sequence table
CREATE TABLE IF NOT EXISTS sl_id_sequence (
    id          BIGINT PRIMARY KEY DEFAULT 1,
    current_max BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT singleton CHECK (id = 1)
);

INSERT INTO sl_id_sequence (id, current_max) VALUES (1, 0)
    ON CONFLICT (id) DO NOTHING;

-- 索引 / Indexes
CREATE INDEX IF NOT EXISTS idx_sl_link_scene_id ON sl_link(scene_id);
CREATE INDEX IF NOT EXISTS idx_sl_link_status ON sl_link(status);
CREATE INDEX IF NOT EXISTS idx_sl_scene_tenant_id ON sl_scene(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sl_domain_entry_tenant_id ON sl_domain_entry(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sl_tenant_credential_ak ON sl_tenant_credential(access_key);

COMMIT;
