## Tasks

### Task 1: Project scaffolding and dependencies

- [x] Create rockspec (`linklet-scm-1.rockspec`) with dependencies (pgmoon, lua-cjson, busted, luacov, luacheck)
- [x] Create `.luacheckrc` configuration
- [x] Create `Makefile` with common targets (test, lint, coverage, build)
- [x] Create project directory structure (`src/`, `spec/`, `test/`, `conf/`, `migrations/`, `deploy/`, `docs/`)
- [x] Create `conf/nginx.conf` and `conf/conf.d/default.conf` with `lua_shared_dict` declaration

### Task 2: Database migrations and schema

- [x] Create `migrations/001_init.sql` with 7 tables (5 domain tables + sl_tenant_credential + sl_id_sequence)
- [x] Create `migrations/001_init_down.sql` for rollback
- [x] Add unique constraints: sl_link.code UNIQUE, sl_domain_entry.domain UNIQUE
- [x] Add foreign key constraints per design

### Task 3: Infrastructure layer (`src/lib/`)

- [x] Implement `src/lib/database.lua` — pgmoon cosocket keepalive pool wrapper (query, exec, transaction)
- [x] Implement `src/lib/cache.lua` — ngx.shared.DICT wrapper (get, set, delete, get_or_set pattern)
- [x] Implement `src/lib/request.lua` — request parameter parsing (JSON body, query params)
- [x] Implement `src/lib/response.lua` — JSON response helper (json, error, not_found)
- [x] Implement `src/lib/obfuscator.lua` — golden ratio obfuscation + Base62 encoding
- [x] Implement `src/lib/id_generator.lua` — segment-based ID allocation from PostgreSQL

### Task 4: Model layer (`src/models/`)

- [x] Implement `src/models/base_model.lua` — shared query execution, row mapping
- [x] Implement `src/models/link.lua` — sl_link CRUD (create, find_by_code, disable, find_by_id)
- [x] Implement `src/models/tenant.lua` — sl_tenant CRUD
- [x] Implement `src/models/tenant_credential.lua` — AK/SK with encrypted SK lookup
- [x] Implement `src/models/scene.lua` — sl_scene CRUD with domain_entry join
- [x] Implement `src/models/domain_entry.lua` — sl_domain_entry CRUD (immutable domain field)

### Task 5: Router and middleware (`src/`)

- [x] Implement `src/router.lua` — route matching, middleware chain execution
- [x] Implement `src/routes.lua` — route definitions (resolution gateway + management API)
- [x] Implement `src/middleware/json.lua` — JSON body parsing middleware
- [x] Implement `src/middleware/validate.lua` — parameter validation middleware
- [x] Implement `src/middleware/auth.lua` — AK/SK HMAC verification middleware
- [x] Implement `src/app.lua` — entry point (init, dispatch)

### Task 6: Handler layer (`src/shorten/`)

- [x] Implement `src/shorten/handler.lua` — create, gen, disable handlers
- [x] Implement `src/shorten/cache_handler.lua` — ngx.shared.DICT cache lookup
- [x] Implement `src/shorten/resolve_handler.lua` — DB query, status/expiry validation, cache write
- [x] Implement `src/shorten/redirect_handler.lua` — HTTP 302 redirect

### Task 7: Unit tests — algorithm and infrastructure (`spec/`)

- [x] `spec/obfuscator_spec.lua` — golden ratio obfuscation, Base62 encoding, collision detection (1-100000 range)
- [x] `spec/id_generator_spec.lua` — segment allocation, consumption, gap tolerance
- [x] `spec/cache_spec.lua` — cache get/set/delete, TTL expiration (mocked ngx.shared.DICT)
- [x] `spec/response_spec.lua` — JSON response format, error responses
- [x] `test/nginx/005-database-models.t` (database scenarios) — query execution (mocked pgmoon)

### Task 8: Unit tests — models (`spec/`)

- [x] `test/nginx/005-database-models.t` (link scenarios) — create, find_by_code, disable, status validation
- [x] `test/nginx/006-runtime-admin.t` (scene scenarios) — find with domain_entry join
- [x] `spec/credential_spec.lua` + `test/nginx/004-auth-crypto.t` — AK lookup, SK decryption verification
- [x] `test/nginx/005-database-models.t` (domain scenarios) — immutability enforcement

### Task 9: Functional tests — API endpoints (`spec/`)

- [x] `spec/handler_spec.lua` + `test/nginx/002-management.t` (create) — create endpoint: valid params, missing params, invalid scene
- [x] `spec/handler_spec.lua` + `test/nginx/002-management.t` (gen) — gen endpoint: valid params, domain not found
- [x] `spec/handler_spec.lua` + `test/nginx/002-management.t` (disable) — disable: active link, already disabled
- [x] `spec/resolve_spec.lua` + `test/nginx/003-resolution.t` — cache hit, cache miss, disabled, expired, not found
- [x] `spec/auth_spec.lua` + `test/nginx/004-auth-crypto.t` — valid AK/SK, invalid signature, unknown AK, disabled credential

### Task 10: E2E tests (`test/e2e/`)

- [x] `test/nginx/003-resolution.t` (HTTP resolution) — full flow: create → resolve (cache miss → DB → cache write → 302)
- [x] `test/nginx/003-resolution.t` (cache hit) — second resolution hits cache (no DB query)
- [x] `test/nginx/003-resolution.t` (disable) — create → disable → resolve returns 410
- [x] `test/nginx/003-resolution.t` (expiry) — create with past expiry → resolve returns 410

### Task 11: Benchmark tests (`test/benchmark/`)

- [x] `test/benchmark/obfuscator_bench.lua` — short code generation throughput
- [x] `test/benchmark/resolution_bench.lua` — resolution with cache hit throughput

### Task 12: CI/CD pipeline (`.github/workflows/`)

- [x] `test.yml` — luacheck + busted + luacov coverage (matrix: lua 5.1, luajit-2.1, lua 5.3)
- [x] `test.yml` acceptance job — Docker + Test::Nginx + real PostgreSQL (needs lint/test)
- [x] `benchmark.yml` — benchmark run on PR
- [x] `release.yml` — tag-triggered Docker image build + GHCR push
- [x] `docs.yml` — documentation files and local link check

### Task 13: Docker and Kubernetes

- [x] `Dockerfile` — multi-stage build based on openresty/openresty
- [x] `deploy/k8s/deployment.yaml` — Deployment + Service
- [x] `deploy/k8s/configmap.yaml` — non-sensitive config
- [x] `deploy/k8s/secret.yaml` — secret template
- [x] `deploy/docker-compose.yml` — local dev (OpenResty + PostgreSQL)

### Task 14: Documentation

- [x] `README.md` — project overview, quick start, architecture summary
- [x] `docs/api.md` — API reference (all endpoints with request/response examples)
- [x] `docs/deployment.md` — Docker/K8s deployment guide
- [x] `docs/development.md` — local development setup guide

## Acceptance evidence

See [acceptance.md](../../../docs/acceptance.md) for issue-by-issue requirements, Test::Nginx cases and results. Runtime acceptance uses real OpenResty and PostgreSQL; unit mocks are supplemental.

All 65 implementation tasks have evidence. CI workflow definitions and Kubernetes templates are locally validated; remote GitHub execution, publishing and cluster deployment are not claimed. Main capability specs are synchronized without archiving the active change.
