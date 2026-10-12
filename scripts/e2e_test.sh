#!/usr/bin/env bash
# Acceptance uses real OpenResty HTTP and PostgreSQL via Test::Nginx.
set -euo pipefail
exec bash "$(dirname "$0")/test_nginx.sh" "$@"
