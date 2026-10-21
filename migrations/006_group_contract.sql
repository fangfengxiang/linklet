-- Maintenance window: stop every pre-006 writer before applying this migration.
-- Rename only; business IDs, codes, grants, credentials and cursor stay intact.
BEGIN;
LOCK TABLE sl_scene, sl_scene_config, sl_short_link, sl_tenant,
    sl_domain_entry, sl_id_sequence IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
    IF EXISTS(SELECT 1 FROM sl_scene s JOIN sl_short_link l ON l.scene_id=s.scene_id
        WHERE s.deleted_at IS NOT NULL) THEN
        RAISE EXCEPTION 'groups with historical links must not be deleted; repair before switch';
    END IF;
END $$;

-- The transitional view captures the old column names; recreate it explicitly.
DROP VIEW sl_link;
ALTER TABLE sl_scene RENAME TO sl_group;
ALTER TABLE sl_scene_config RENAME TO sl_group_config;
ALTER TABLE sl_group RENAME COLUMN scene_id TO group_id;
ALTER TABLE sl_group_config RENAME COLUMN scene_id TO group_id;
ALTER TABLE sl_short_link RENAME COLUMN scene_id TO group_id;
ALTER TABLE sl_tenant RENAME COLUMN scene_ids TO group_ids;
ALTER SEQUENCE sl_scene_scene_id_seq RENAME TO sl_group_group_id_seq;
ALTER SEQUENCE sl_scene_id_seq RENAME TO sl_group_id_seq;
ALTER SEQUENCE sl_scene_config_id_seq RENAME TO sl_group_config_id_seq;
CREATE VIEW sl_link AS SELECT id, code, target_url, group_id AS scene_id,
    status, expires_at, created_at, disabled_at FROM sl_short_link;

DROP TRIGGER sl_scene_binding ON sl_group;
DROP FUNCTION sl_scene_binding();
CREATE FUNCTION sl_group_binding() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE domain_state smallint;
BEGIN
    IF TG_OP='UPDATE' THEN
        IF NEW.group_id IS DISTINCT FROM OLD.group_id THEN
            RAISE EXCEPTION 'group_id is immutable';
        END IF;
        -- UPDATE already holds the same group row lock acquired by link inserts.
        -- Include disabled/expired links: issued URLs and codes are permanent.
        IF (NEW.domain_entry_id IS DISTINCT FROM OLD.domain_entry_id OR
            (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)) AND EXISTS(
            SELECT 1 FROM sl_short_link WHERE group_id=OLD.group_id) THEN
            RAISE EXCEPTION 'group with links cannot change domain or be deleted';
        END IF;
    END IF;
    IF TG_OP='INSERT' OR NEW.domain_entry_id IS DISTINCT FROM OLD.domain_entry_id
        OR (OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL) THEN
        SELECT status INTO domain_state FROM sl_domain_entry
            WHERE id=NEW.domain_entry_id AND deleted_at IS NULL FOR UPDATE;
        IF domain_state IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'domain must be deployed'; END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER sl_group_binding BEFORE INSERT OR UPDATE ON sl_group
    FOR EACH ROW EXECUTE FUNCTION sl_group_binding();

CREATE FUNCTION sl_link_group_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE bound_group sl_group%ROWTYPE;
BEGIN
    SELECT * INTO bound_group FROM sl_group WHERE group_id=NEW.group_id FOR UPDATE;
    IF NOT FOUND OR bound_group.status<>1 OR bound_group.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'group must be enabled';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM sl_domain_entry WHERE id=bound_group.domain_entry_id
        AND status=2 AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'domain must be deployed';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER sl_link_group_guard BEFORE INSERT ON sl_short_link
    FOR EACH ROW EXECUTE FUNCTION sl_link_group_guard();

CREATE OR REPLACE FUNCTION sl_immutable_link() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'short codes cannot be deleted or reused'; END IF;
    IF NEW.code IS DISTINCT FROM OLD.code OR NEW.target_url IS DISTINCT FROM OLD.target_url
        OR NEW.group_id IS DISTINCT FROM OLD.group_id THEN
        RAISE EXCEPTION 'short code, target and group are immutable';
    END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION sl_immutable_domain() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status < OLD.status OR NEW.status > OLD.status + 1 THEN
        RAISE EXCEPTION 'domain lifecycle must follow new -> deployed -> offline';
    END IF;
    IF OLD.status>=2 AND NEW.domain IS DISTINCT FROM OLD.domain THEN
        RAISE EXCEPTION 'deployed domain is immutable';
    END IF;
    IF ((NEW.status=3 AND OLD.status<>3) OR
        (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)) AND EXISTS(
        SELECT 1 FROM sl_group WHERE domain_entry_id=OLD.id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'domain is still bound to a group';
    END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION sl_tenant_grants() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS(SELECT 1 FROM unnest(NEW.group_ids) x LEFT JOIN sl_group g ON g.group_id=x
        WHERE x IS NULL OR g.group_id IS NULL OR g.deleted_at IS NOT NULL) THEN
        RAISE EXCEPTION 'grants must reference existing groups';
    END IF;
    NEW.group_ids := ARRAY(SELECT DISTINCT x FROM unnest(NEW.group_ids) x ORDER BY x);
    RETURN NEW;
END $$;
COMMIT;
