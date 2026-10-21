#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PGHOST=127.0.0.1 PGPORT="${LINKLET_TEST_PGPORT:-5432}" PGUSER=linklet PGPASSWORD=acceptance_only
migration_db=linklet_migration_test
# This database exists only in the disposable acceptance PostgreSQL service.
createdb "$migration_db"
psql -v ON_ERROR_STOP=1 -d "$migration_db" -f migrations/001_init.sql
psql -v ON_ERROR_STOP=1 -d "$migration_db" -f migrations/003_integrity.sql
psql -v ON_ERROR_STOP=1 -d "$migration_db" -f migrations/003_integrity_down.sql
psql -v ON_ERROR_STOP=1 -d "$migration_db" -f migrations/001_init_down.sql
remaining=$(psql -At -d "$migration_db" -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'")
[ "$remaining" = 0 ]
dropdb "$migration_db"
echo 'Migration up/down verified in disposable database'

# Exercise historical data -> expansion -> backup/restore -> maintenance switch.
createdb "$migration_db"
restore_db=linklet_restore_test
createdb "$restore_db"
migration_tmp=$(mktemp -d)
trap 'dropdb --if-exists "$migration_db"; dropdb --if-exists "$restore_db"; rm -rf "$migration_tmp"' EXIT
psql -v ON_ERROR_STOP=1 -d "$migration_db" -f migrations/001_init.sql
psql -v ON_ERROR_STOP=1 -d "$migration_db" -f migrations/003_integrity.sql
psql -v ON_ERROR_STOP=1 -d "$migration_db" <<'SQL'
INSERT INTO sl_tenant(id,name,scene_ids) VALUES(1,'legacy',NULL),(2,'shared','{100,100}');
INSERT INTO sl_domain_entry(id,tenant_id,domain,status) VALUES
 (1,1,'s.example.com',1),(2,1,'disabled.example.com',2),(3,1,'deleted.example.com',3);
INSERT INTO sl_scene(scene_id,tenant_id,name,domain_entry_id) VALUES(100,1,'legacy-scene',1);
INSERT INTO sl_link(code,target_url,scene_id,expires_at) VALUES('LegacyCode','https://example.com/keep',100,NULL);
INSERT INTO sl_scene_config(scene_id,config_key,config_value) VALUES(100,'legacy_setting','keep');
INSERT INTO sl_tenant_credential(tenant_id,access_key,secret_key_enc) VALUES(1,'legacy-ak','ciphertext-preserved');
UPDATE sl_id_sequence SET current_max=424242 WHERE id=1;
SQL
psql -XAt -v ON_ERROR_STOP=1 -d "$migration_db" -f scripts/database_snapshot.sql > "$migration_tmp/before.json"
psql -v ON_ERROR_STOP=1 -d "$migration_db" -f migrations/004_v02_expand.sql
# Old code can still write after expansion; switch backfill must capture this.
psql -v ON_ERROR_STOP=1 -d "$migration_db" -c "INSERT INTO sl_scene(scene_id,tenant_id,name,domain_entry_id) VALUES(101,1,'late-old-writer',1)"
psql -XAt -v ON_ERROR_STOP=1 -d "$migration_db" -f scripts/database_snapshot.sql > "$migration_tmp/before.json"
PGDATABASE="$migration_db" bash scripts/backup_database.sh "$migration_tmp/backup"
pg_restore --exit-on-error -d "$restore_db" "$migration_tmp/backup/database.dump"
psql -XAt -v ON_ERROR_STOP=1 -d "$restore_db" -f scripts/database_snapshot.sql > "$migration_tmp/restored.json"
cmp "$migration_tmp/before.json" "$migration_tmp/restored.json"
# Unsafe switch must fail atomically, preserving old domain semantics.
psql -v ON_ERROR_STOP=1 -d "$migration_db" -c "INSERT INTO sl_scene(scene_id,tenant_id,name) VALUES(102,1,'unbound')"
if psql -v ON_ERROR_STOP=1 -d "$migration_db" -f migrations/005_v02_switch.sql > "$migration_tmp/rejected.log" 2>&1; then
    echo 'Unsafe migration unexpectedly succeeded' >&2; exit 1
fi
[ "$(psql -At -d "$migration_db" -c 'SELECT status FROM sl_domain_entry WHERE id=1')" = 1 ]
psql -v ON_ERROR_STOP=1 -d "$migration_db" -c "DELETE FROM sl_scene WHERE scene_id=102"
echo 'Unbound scene correctly blocked switch without partial state conversion'
psql -v ON_ERROR_STOP=1 -d "$migration_db" -f migrations/005_v02_switch.sql
psql -XAt -v ON_ERROR_STOP=1 -d "$migration_db" -f scripts/database_snapshot.sql > "$migration_tmp/after.json"
cmp "$migration_tmp/before.json" "$migration_tmp/after.json"
psql -v ON_ERROR_STOP=1 -d "$migration_db" <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE')<>7
 THEN RAISE EXCEPTION 'expected seven tables'; END IF;
 IF (SELECT scene_ids FROM sl_tenant WHERE id=1)<>ARRAY[100,101]::bigint[] OR
    (SELECT scene_ids FROM sl_tenant WHERE id=2)<>ARRAY[100]::bigint[]
 THEN RAISE EXCEPTION 'grants not preserved/deduplicated'; END IF;
 IF (SELECT array_agg(status ORDER BY id) FROM sl_domain_entry)<>ARRAY[2,3,3]::smallint[]
 THEN RAISE EXCEPTION 'invalid domain mapping'; END IF;
 IF (SELECT current_max FROM sl_id_sequence WHERE sequence_key=1)<>424242
 THEN RAISE EXCEPTION 'cursor changed'; END IF;
 IF (SELECT secret_key_enc FROM sl_tenant_credential WHERE access_key='legacy-ak')<>'ciphertext-preserved'
 THEN RAISE EXCEPTION 'credential changed'; END IF;
END $$;
SQL
echo 'v0.2 seven-table migration, late backfill, code/ID/AK snapshots and backup restore verified'

# Independent Scene -> Group switch; 001/003/004/005 remain historical migrations.
psql -v ON_ERROR_STOP=1 -d "$migration_db" -c "UPDATE sl_scene SET deleted_at=NOW() WHERE scene_id=100"
if psql -v ON_ERROR_STOP=1 -d "$migration_db" -f migrations/006_group_contract.sql > "$migration_tmp/group-rejected.log" 2>&1; then
    echo 'Unsafe Group switch unexpectedly succeeded' >&2; exit 1
fi
[ "$(psql -At -d "$migration_db" -c "SELECT to_regclass('sl_scene') IS NOT NULL AND to_regclass('sl_group') IS NULL")" = t ]
psql -v ON_ERROR_STOP=1 -d "$migration_db" -c "UPDATE sl_scene SET deleted_at=NULL WHERE scene_id=100"
psql -v ON_ERROR_STOP=1 -d "$migration_db" -f migrations/006_group_contract.sql
psql -XAt -v ON_ERROR_STOP=1 -d "$migration_db" -f scripts/database_snapshot.sql > "$migration_tmp/group.json"
cmp "$migration_tmp/after.json" "$migration_tmp/group.json"
psql -v ON_ERROR_STOP=1 -d "$migration_db" <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE')<>7
 THEN RAISE EXCEPTION 'expected seven Group tables'; END IF;
 IF to_regclass('sl_scene') IS NOT NULL OR to_regclass('sl_group_config') IS NULL
 THEN RAISE EXCEPTION 'rename incomplete'; END IF;
 IF (SELECT group_ids FROM sl_tenant WHERE id=1)<>ARRAY[100,101]::bigint[] OR
    (SELECT group_ids FROM sl_tenant WHERE id=2)<>ARRAY[100]::bigint[]
 THEN RAISE EXCEPTION 'Group grants changed'; END IF;
 IF (SELECT group_id FROM sl_short_link WHERE code='LegacyCode')<>100
 THEN RAISE EXCEPTION 'link ownership changed'; END IF;
 IF (SELECT config_value FROM sl_group_config WHERE group_id=100 AND config_key='legacy_setting') IS DISTINCT FROM 'keep'
 THEN RAISE EXCEPTION 'group configuration changed'; END IF;
 IF (SELECT secret_key_enc FROM sl_tenant_credential WHERE access_key='legacy-ak')<>'ciphertext-preserved'
 THEN RAISE EXCEPTION 'credential ciphertext changed'; END IF;
END $$;
SQL
echo 'Group rename preserved seven tables, links, grants, credentials and cursor'
