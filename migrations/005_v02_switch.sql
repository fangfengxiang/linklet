-- Maintenance-window switch: stop ALL old application writers, back up and
-- verify first. Legacy columns are retained; destructive contract is deferred.
BEGIN;
LOCK TABLE sl_scene, sl_domain_entry, sl_link, sl_tenant, sl_id_sequence IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
    IF EXISTS(SELECT 1 FROM sl_scene WHERE domain_entry_id IS NULL) THEN
        RAISE EXCEPTION 'v0.2 requires a domain binding for every scene; repair before switch';
    END IF;
    IF EXISTS(SELECT 1 FROM sl_tenant t CROSS JOIN LATERAL unnest(t.scene_ids) x
        LEFT JOIN sl_scene s ON s.scene_id=x
        WHERE x IS NULL OR s.scene_id IS NULL OR s.deleted_at IS NOT NULL) THEN
        RAISE EXCEPTION 'existing grants reference missing/deleted scenes; repair before switch';
    END IF;
    IF EXISTS(SELECT 1 FROM sl_domain_entry WHERE
        domain !~* '^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$' OR domain LIKE '%..%'
        OR length(domain)>253 OR domain ~ '(^|[.])-|-(\.|$)'
        OR EXISTS(SELECT 1 FROM unnest(string_to_array(domain,'.')) label WHERE length(label)>63)) THEN
        RAISE EXCEPTION 'domains must be DNS hostnames without scheme or port; review historical URLs';
    END IF;
END $$;
-- Repeat backfill after old writers have stopped.
UPDATE sl_tenant t SET scene_ids = ARRAY(
    SELECT DISTINCT x FROM unnest(t.scene_ids ||
        ARRAY(SELECT scene_id FROM sl_scene WHERE tenant_id=t.id)) x ORDER BY x);
DROP TRIGGER sl_domain_terminal ON sl_domain_entry;
DROP TRIGGER sl_domain_immutable ON sl_domain_entry;
-- Old active -> deployed; disabled/deleted -> offline. Never reinterpret 1 as new.
UPDATE sl_domain_entry SET status=CASE status WHEN 1 THEN 2 ELSE 3 END;
ALTER TABLE sl_domain_entry ALTER COLUMN status SET DEFAULT 1;
ALTER TABLE sl_domain_entry ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE sl_scene DROP CONSTRAINT sl_scene_domain_tenant_fk;
ALTER TABLE sl_scene ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE sl_scene ALTER COLUMN domain_entry_id SET NOT NULL;
ALTER TABLE sl_scene ADD CONSTRAINT sl_scene_business_id UNIQUE(scene_id);
ALTER TABLE sl_scene_config DROP CONSTRAINT sl_scene_config_scene_id_fkey;
ALTER TABLE sl_link DROP CONSTRAINT sl_link_scene_id_fkey;
ALTER TABLE sl_scene DROP CONSTRAINT sl_scene_pkey;
ALTER TABLE sl_scene ADD PRIMARY KEY(id);
ALTER TABLE sl_scene_config ADD FOREIGN KEY(scene_id) REFERENCES sl_scene(scene_id);
ALTER TABLE sl_link ADD FOREIGN KEY(scene_id) REFERENCES sl_scene(scene_id);
ALTER TABLE sl_id_sequence DROP CONSTRAINT sl_id_sequence_pkey;
ALTER TABLE sl_id_sequence DROP CONSTRAINT singleton;
ALTER TABLE sl_id_sequence ADD PRIMARY KEY(sequence_key);
ALTER TABLE sl_scene_config ALTER COLUMN config_key TYPE VARCHAR(128);
ALTER TABLE sl_scene_config ALTER COLUMN config_value SET NOT NULL;
DROP VIEW sl_short_link;
ALTER TABLE sl_link RENAME TO sl_short_link;
-- Transitional SQL alias for operational tooling, NOT old application coexistence.
CREATE VIEW sl_link AS SELECT * FROM sl_short_link;
DROP TRIGGER sl_scene_terminal ON sl_scene;
DROP TRIGGER sl_tenant_terminal ON sl_tenant;

CREATE OR REPLACE FUNCTION sl_immutable_domain() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status < OLD.status OR NEW.status > OLD.status + 1 THEN
        RAISE EXCEPTION 'domain lifecycle must follow new -> deployed -> offline';
    END IF;
    IF OLD.status >= 2 AND NEW.domain IS DISTINCT FROM OLD.domain THEN
        RAISE EXCEPTION 'deployed domain is immutable';
    END IF;
    IF NEW.status=3 AND OLD.status<>3 AND EXISTS(
        SELECT 1 FROM sl_scene WHERE domain_entry_id=OLD.id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'domain is still bound to a scene';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER sl_domain_immutable BEFORE UPDATE ON sl_domain_entry
    FOR EACH ROW EXECUTE FUNCTION sl_immutable_domain();

CREATE FUNCTION sl_scene_binding() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE domain_state smallint;
BEGIN
    IF TG_OP='UPDATE' AND NEW.scene_id IS DISTINCT FROM OLD.scene_id THEN
        RAISE EXCEPTION 'scene_id is immutable';
    END IF;
    IF TG_OP='INSERT' OR NEW.domain_entry_id IS DISTINCT FROM OLD.domain_entry_id
        OR (OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL) THEN
        SELECT status INTO domain_state FROM sl_domain_entry
            WHERE id=NEW.domain_entry_id AND deleted_at IS NULL FOR UPDATE;
        IF domain_state IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'domain must be deployed'; END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER sl_scene_binding BEFORE INSERT OR UPDATE ON sl_scene
    FOR EACH ROW EXECUTE FUNCTION sl_scene_binding();

CREATE FUNCTION sl_tenant_grants() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS(SELECT 1 FROM unnest(NEW.scene_ids) x LEFT JOIN sl_scene s ON s.scene_id=x
        WHERE x IS NULL OR s.scene_id IS NULL OR s.deleted_at IS NOT NULL) THEN
        RAISE EXCEPTION 'grants must reference existing scenes';
    END IF;
    NEW.scene_ids := ARRAY(SELECT DISTINCT x FROM unnest(NEW.scene_ids) x ORDER BY x);
    RETURN NEW;
END $$;
CREATE TRIGGER sl_tenant_grants BEFORE INSERT OR UPDATE OF scene_ids ON sl_tenant
    FOR EACH ROW EXECUTE FUNCTION sl_tenant_grants();

CREATE FUNCTION sl_sequence_monotonic() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'sequence cannot be deleted'; END IF;
    IF NEW.sequence_key<>OLD.sequence_key OR NEW.current_max<OLD.current_max THEN
        RAISE EXCEPTION 'sequence key immutable and cursor monotonic';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER sl_sequence_monotonic BEFORE UPDATE OR DELETE ON sl_id_sequence
    FOR EACH ROW EXECUTE FUNCTION sl_sequence_monotonic();
CREATE FUNCTION sl_credential_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'access keys cannot be reused'; END IF;
    IF NEW.access_key<>OLD.access_key OR NEW.secret_key_enc<>OLD.secret_key_enc
        OR NEW.tenant_id<>OLD.tenant_id THEN RAISE EXCEPTION 'rotate with a new credential'; END IF;
    IF NEW.status=2 AND OLD.status=1 THEN NEW.disabled_at := NOW(); END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER sl_credential_immutable BEFORE UPDATE OR DELETE ON sl_tenant_credential
    FOR EACH ROW EXECUTE FUNCTION sl_credential_immutable();
CREATE OR REPLACE FUNCTION sl_cache_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE sl_id_sequence SET cache_revision=cache_revision+1 WHERE sequence_key=1;
    RETURN NEW;
END $$;
-- Existing UPDATE triggers now cover expiry, domain binding and soft deletion too.
COMMIT;
