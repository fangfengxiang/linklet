.PHONY: test lint coverage build clean install

LUA_VERSION ?= 5.1
LUAROCKS ?= luarocks
BUSTED ?= busted
LUACOV ?= luacov
LUACHECK ?= luacheck

install:
	$(LUAROCKS) make --local 2>/dev/null || true

lint:
	$(LUACHECK) src/ spec/ --codes

test:
	$(BUSTED) spec/ --pattern="_spec"

coverage:
	$(BUSTED) spec/ -c "luacov"
	$(LUACOV) src/
	@cat luacov.report.out | grep -E "^Total|src/"
	@THRESHOLD=80; COV=$$(grep "^Total" luacov.report.out | awk '{print $$NF}' | tr -d '%'); \
	if [ -z "$$COV" ]; then echo "Coverage: unable to parse"; exit 1; fi; \
	if [ $$(echo "$$COV >= $$THRESHOLD" | bc) -eq 1 ]; then \
		echo "✓ Coverage $$COV% >= $$THRESHOLD%"; \
	else \
		echo "✗ Coverage $$COV% < $$THRESHOLD%"; exit 1; \
	fi

e2e:
	$(BUSTED) test/e2e/ --pattern="_spec"

benchmark:
	lua test/benchmark/obfuscator_bench.lua

build:
	docker build -t linklet:latest .

clean:
	rm -f luacov.stats.out luacov.report.out

all: lint test coverage
