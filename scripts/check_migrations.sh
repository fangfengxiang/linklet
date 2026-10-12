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
