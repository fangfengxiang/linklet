#!/usr/bin/env bash
# Uses standard PG* environment. Output contains business data; protect the directory.
set -euo pipefail
umask 077
backup_dir=${1:?Usage: backup_database.sh NEW_OUTPUT_DIRECTORY (set PGHOST/PGDATABASE/etc)}
mkdir -m 700 "$backup_dir"
pg_dump --format=custom --file="$backup_dir/database.dump"
psql -XAt -v ON_ERROR_STOP=1 -f "$(dirname "$0")/database_snapshot.sql" > "$backup_dir/snapshot.json"
printf 'Backup and invariant snapshot saved. Restore into an isolated database before switching.\n'
