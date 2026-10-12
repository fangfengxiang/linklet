.PHONY: install lint test acceptance acceptance-docker e2e coverage benchmark build docs-check
LUAROCKS ?= luarocks
BUSTED ?= busted
LUACOV ?= luacov
LUACHECK ?= luacheck
install:
	$(LUAROCKS) make --local
lint:
	$(LUACHECK) src/ spec/ --codes
test:
	$(BUSTED) spec/
acceptance:
	bash scripts/test_nginx.sh
acceptance-docker:
	docker compose -p linklet-acceptance -f deploy/acceptance-compose.yml up --build --abort-on-container-exit --exit-code-from acceptance
e2e: acceptance
coverage:
	: > luacov.stats.out
	$(BUSTED) spec/ --coverage
	LINKLET_COVERAGE=1 bash scripts/test_nginx.sh
	$(LUACOV) src/
	python3 scripts/check_coverage.py
benchmark:
	LUA_PATH='src/?.lua;;' lua test/benchmark/obfuscator_bench.lua
build:
	docker build --target runtime -t linklet:latest .
docs-check:
	python3 scripts/check_docs.py
