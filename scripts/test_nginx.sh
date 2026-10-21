#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export TEST_NGINX_BINARY="${TEST_NGINX_BINARY:-$(command -v openresty)}"
export TEST_NGINX_SERVROOT="$PWD/.test-nginx"
export TEST_NGINX_PORT="${TEST_NGINX_PORT:-1984}"
export LINKLET_TEST_PGPORT="${LINKLET_TEST_PGPORT:-15432}"
export PGHOST=127.0.0.1 PGPORT="$LINKLET_TEST_PGPORT" PGDATABASE=linklet_test PGUSER=linklet PGPASSWORD=acceptance_only
# Public fixture key is restricted to this test runner and disposable database.
export LINKLET_ENCRYPTION_KEY="$(printf 'ab%.0s' {1..32})"
if [ "$#" -eq 0 ]; then set -- test/nginx/*.t; fi
if [ "${LINKLET_COVERAGE:-0}" = 1 ]; then
    export LINKLET_COVERAGE_DIR
    LINKLET_COVERAGE_DIR=$(mktemp -d)
    trap 'rm -rf "$LINKLET_COVERAGE_DIR"' EXIT
fi
prove -Itest/nginx/lib "$@"
if [ "${LINKLET_COVERAGE:-0}" = 1 ]; then
    luajit scripts/merge_coverage.lua luacov.stats.out "$LINKLET_COVERAGE_DIR"/*.out
fi
