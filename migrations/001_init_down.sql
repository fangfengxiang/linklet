-- migrations/001_init_down.sql
-- Rollback for linklet core schema

BEGIN;

DROP TABLE IF EXISTS sl_id_sequence;
DROP TABLE IF EXISTS sl_tenant_credential;
DROP TABLE IF EXISTS sl_link;
DROP TABLE IF EXISTS sl_scene_config;
DROP TABLE IF EXISTS sl_scene;
DROP TABLE IF EXISTS sl_domain_entry;
DROP TABLE IF EXISTS sl_tenant;

COMMIT;
