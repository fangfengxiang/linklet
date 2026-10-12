-- Upgrade existing installations without dropping data.
BEGIN;
ALTER TABLE sl_link ADD CONSTRAINT sl_link_status_check CHECK (status IN (1,2));
ALTER TABLE sl_tenant ADD CONSTRAINT sl_tenant_status_check CHECK (status IN (1,2));
ALTER TABLE sl_scene ADD CONSTRAINT sl_scene_status_check CHECK (status IN (1,2));
ALTER TABLE sl_tenant_credential ADD CONSTRAINT sl_credential_status_check CHECK (status IN (1,2));
ALTER TABLE sl_domain_entry ADD CONSTRAINT sl_domain_status_check CHECK (status IN (1,2,3));
ALTER TABLE sl_domain_entry ADD CONSTRAINT sl_domain_tenant_unique UNIQUE (id,tenant_id);
ALTER TABLE sl_scene ADD CONSTRAINT sl_scene_domain_tenant_fk
    FOREIGN KEY (domain_entry_id,tenant_id) REFERENCES sl_domain_entry(id,tenant_id);
ALTER TABLE sl_id_sequence ADD COLUMN cache_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE sl_id_sequence ADD CONSTRAINT sl_sequence_bounds CHECK (current_max BETWEEN 0 AND 4294967295);

CREATE FUNCTION sl_terminal_status() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status < OLD.status THEN
        RAISE EXCEPTION 'disabled or deleted records cannot be re-enabled';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER sl_link_terminal BEFORE UPDATE ON sl_link FOR EACH ROW EXECUTE FUNCTION sl_terminal_status();
CREATE TRIGGER sl_domain_terminal BEFORE UPDATE ON sl_domain_entry FOR EACH ROW EXECUTE FUNCTION sl_terminal_status();
CREATE TRIGGER sl_tenant_terminal BEFORE UPDATE ON sl_tenant FOR EACH ROW EXECUTE FUNCTION sl_terminal_status();
CREATE TRIGGER sl_scene_terminal BEFORE UPDATE ON sl_scene FOR EACH ROW EXECUTE FUNCTION sl_terminal_status();
CREATE TRIGGER sl_credential_terminal BEFORE UPDATE ON sl_tenant_credential FOR EACH ROW EXECUTE FUNCTION sl_terminal_status();

CREATE FUNCTION sl_immutable_domain() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.domain IS DISTINCT FROM OLD.domain OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION 'domain and owner are immutable';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER sl_domain_immutable BEFORE UPDATE ON sl_domain_entry FOR EACH ROW EXECUTE FUNCTION sl_immutable_domain();

CREATE FUNCTION sl_immutable_link() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'short codes cannot be deleted or reused'; END IF;
    IF NEW.code IS DISTINCT FROM OLD.code OR NEW.target_url IS DISTINCT FROM OLD.target_url
        OR NEW.scene_id IS DISTINCT FROM OLD.scene_id THEN
        RAISE EXCEPTION 'short code, target and scene are immutable';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER sl_link_immutable BEFORE UPDATE OR DELETE ON sl_link FOR EACH ROW EXECUTE FUNCTION sl_immutable_link();

CREATE FUNCTION sl_cache_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        UPDATE sl_id_sequence SET cache_revision = cache_revision + 1 WHERE id=1;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER sl_link_cache_changed AFTER UPDATE ON sl_link FOR EACH ROW EXECUTE FUNCTION sl_cache_changed();
CREATE TRIGGER sl_scene_cache_changed AFTER UPDATE ON sl_scene FOR EACH ROW EXECUTE FUNCTION sl_cache_changed();
CREATE TRIGGER sl_domain_cache_changed AFTER UPDATE ON sl_domain_entry FOR EACH ROW EXECUTE FUNCTION sl_cache_changed();
CREATE TRIGGER sl_tenant_cache_changed AFTER UPDATE ON sl_tenant FOR EACH ROW EXECUTE FUNCTION sl_cache_changed();
COMMIT;
