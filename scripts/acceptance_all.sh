#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check_migrations.sh
luarocks make --tree=/tmp/linklet-installed --deps-mode=none
LUA_PATH="/tmp/linklet-installed/share/lua/5.1/?.lua;/tmp/linklet-installed/share/lua/5.1/?/init.lua;;" luajit -e 'assert(require("linklet").init)'
python3 scripts/check_boundaries.py
luacheck lib/ src/ spec/ --codes
: > luacov.stats.out
busted spec/ --coverage
LINKLET_COVERAGE=1 bash scripts/test_nginx.sh
LINKLET_COVERAGE=1 bash scripts/test_nginx.sh test/nginx/multi-instance/001-runtime.t
luacov
python3 scripts/check_coverage.py
python3 scripts/check_docs.py
