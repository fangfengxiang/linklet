-- Online-compatible expansion. Run with the old application still serving.
BEGIN;
ALTER TABLE sl_tenant ADD COLUMN deleted_at TIMESTAMPTZ;
UPDATE sl_tenant t SET scene_ids = ARRAY(
    SELECT DISTINCT x FROM unnest(COALESCE(t.scene_ids, '{}') ||
        ARRAY(SELECT scene_id FROM sl_scene WHERE tenant_id=t.id)) x ORDER BY x);
ALTER TABLE sl_tenant ALTER COLUMN scene_ids SET NOT NULL;
ALTER TABLE sl_scene ADD COLUMN id BIGSERIAL UNIQUE;
ALTER TABLE sl_scene ADD COLUMN deleted_at TIMESTAMPTZ;
ALTER TABLE sl_scene ADD CONSTRAINT sl_scene_uint32 CHECK(scene_id BETWEEN 1 AND 4294967295);
ALTER TABLE sl_domain_entry ADD COLUMN tag VARCHAR(100);
UPDATE sl_domain_entry SET tag=LEFT(label,100);
ALTER TABLE sl_scene_config ADD COLUMN description VARCHAR(255);
ALTER TABLE sl_scene_config ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE sl_tenant_credential ADD COLUMN description VARCHAR(255);
ALTER TABLE sl_tenant_credential ADD COLUMN disabled_at TIMESTAMPTZ;
ALTER TABLE sl_link ADD COLUMN disabled_at TIMESTAMPTZ;
ALTER TABLE sl_id_sequence ADD COLUMN sequence_key INTEGER NOT NULL DEFAULT 1 UNIQUE CHECK(sequence_key > 0);
ALTER TABLE sl_id_sequence ADD COLUMN step INTEGER NOT NULL DEFAULT 1000 CHECK(step BETWEEN 1 AND 1000000);
ALTER TABLE sl_id_sequence ADD COLUMN created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE sl_id_sequence ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
CREATE INDEX idx_sl_scene_domain ON sl_scene(domain_entry_id);
CREATE INDEX idx_sl_credential_tenant ON sl_tenant_credential(tenant_id);
CREATE VIEW sl_short_link AS SELECT * FROM sl_link;
COMMIT;
