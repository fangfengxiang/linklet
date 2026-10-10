## Tasks

### Task 1: Project scaffolding and dependencies

- [ ] Create rockspec (`linklet-scm-1.rockspec`) with dependencies (pgmoon, lua-cjson, busted, luacov, luacheck)
- [ ] Create `.luacheckrc` configuration
- [ ] Create `Makefile` with common targets (test, lint, coverage, build)
- [ ] Create project directory structure (`src/`, `spec/`, `test/`, `conf/`, `migrations/`, `deploy/`, `docs/`)
- [ ] Create `conf/nginx.conf` and `conf/conf.d/default.conf` with `lua_shared_dict` declaration

### Task 2: Database migrations and schema

- [ ] Create `migrations/001_init.sql` with 6 tables (sl_tenant, sl_domain_entry, sl_scene, sl_scene_config, sl_link, sl_id_sequence)
- [ ] Create `migrations/001_init_down.sql` for rollback
- [ ] Add unique constraints: sl_link.code UNIQUE, sl_domain_entry.domain UNIQUE
- [ ] Add foreign key constraints per design

### Task 3: Infrastructure layer (`src/lib/`)

- [ ] Implement `src/lib/database.lua` — pgmoon connection pool wrapper (query, exec, transaction)
- [ ] Implement `src/lib/cache.lua` — ngx.shared.DICT wrapper (get, set, delete, get_or_set pattern)
- [ ] Implement `src/lib/request.lua` — request parameter parsing (JSON body, query params)
- [ ] Implement `src/lib/response.lua` — JSON response helper (json, error, not_found)
- [ ] Implement `src/lib/obfuscator.lua` — golden ratio obfuscation + Base62 encoding
- [ ] Implement `src/lib/id_generator.lua` — segment-based ID allocation from PostgreSQL

### Task 4: Model layer (`src/models/`)

- [ ] Implement `src/models/base_model.lua` — shared query execution, row mapping
- [ ] Implement `src/models/link.lua` — sl_link CRUD (create, find_by_code, disable, find_by_id)
- [ ] Implement `src/models/tenant.lua` — sl_tenant CRUD
- [ ] Implement `src/models/tenant_credential.lua` — AK/SK with encrypted SK lookup
- [ ] Implement `src/models/scene.lua` — sl_scene CRUD with domain_entry join
- [ ] Implement `src/models/domain_entry.lua` — sl_domain_entry CRUD (immutable domain field)

### Task 5: Router and middleware (`src/`)

- [ ] Implement `src/router.lua` — route matching, middleware chain execution
- [ ] Implement `src/routes.lua` — route definitions (resolution gateway + management API)
- [ ] Implement `src/middleware/json.lua` — JSON body parsing middleware
- [ ] Implement `src/middleware/validate.lua` — parameter validation middleware
- [ ] Implement `src/middleware/auth.lua` — AK/SK HMAC verification middleware
- [ ] Implement `src/app.lua` — entry point (init, dispatch)

### Task 6: Handler layer (`src/shorten/`)

- [ ] Implement `src/shorten/handler.lua` — create, gen, disable handlers
- [ ] Implement `src/shorten/cache_handler.lua` — ngx.shared.DICT cache lookup
- [ ] Implement `src/shorten/resolve_handler.lua` — DB query, status/expiry validation, cache write
- [ ] Implement `src/shorten/redirect_handler.lua` — HTTP 302 redirect

### Task 7: Unit tests — algorithm and infrastructure (`spec/`)

- [ ] `spec/obfuscator_spec.lua` — golden ratio obfuscation, Base62 encoding, collision detection (1-100000 range)
- [ ] `spec/id_generator_spec.lua` — segment allocation, consumption, gap tolerance
- [ ] `spec/cache_spec.lua` — cache get/set/delete, TTL expiration (mocked ngx.shared.DICT)
- [ ] `spec/response_spec.lua` — JSON response format, error responses
- [ ] `spec/database_spec.lua` — query execution (mocked pgmoon)

### Task 8: Unit tests — models (`spec/`)

- [ ] `spec/link_model_spec.lua` — create, find_by_code, disable, status validation
- [ ] `spec/scene_model_spec.lua` — find with domain_entry join
- [ ] `spec/tenant_credential_spec.lua` — AK lookup, SK decryption verification
- [ ] `spec/domain_entry_model_spec.lua` — immutability enforcement

### Task 9: Functional tests — API endpoints (`spec/`)

- [ ] `spec/create_handler_spec.lua` — create endpoint: valid params, missing params, invalid scene
- [ ] `spec/gen_handler_spec.lua` — gen endpoint: valid params, domain not found
- [ ] `spec/disable_handler_spec.lua` — disable: active link, already disabled
- [ ] `spec/resolve_handler_spec.lua` — cache hit, cache miss, disabled, expired, not found
- [ ] `spec/auth_middleware_spec.lua` — valid AK/SK, invalid signature, unknown AK, disabled credential

### Task 10: E2E tests (`test/e2e/`)

- [ ] `test/e2e/resolution_spec.lua` — full flow: create → resolve (cache miss → DB → cache write → 302)
- [ ] `test/e2e/cache_hit_spec.lua` — second resolution hits cache (no DB query)
- [ ] `test/e2e/disable_flow_spec.lua` — create → disable → resolve returns 410
- [ ] `test/e2e/expire_flow_spec.lua` — create with past expiry → resolve returns 410

### Task 11: Benchmark tests (`test/benchmark/`)

- [ ] `test/benchmark/obfuscator_bench.lua` — short code generation throughput
- [ ] `test/benchmark/resolution_bench.lua` — resolution with cache hit throughput

### Task 12: CI/CD pipeline (`.github/workflows/`)

- [ ] `test.yml` — luacheck + busted + luacov coverage (matrix: lua 5.1, luajit-2.1, lua 5.3)
- [ ] `e2e.yml` — Docker build + E2E test (needs test)
- [ ] `benchmark.yml` — benchmark run on PR
- [ ] `release.yml` — tag-triggered Docker image build + GHCR push
- [ ] `docs.yml` — documentation check

### Task 13: Docker and Kubernetes

- [ ] `Dockerfile` — multi-stage build based on openresty/openresty
- [ ] `deploy/k8s/deployment.yaml` — Deployment + Service
- [ ] `deploy/k8s/configmap.yaml` — non-sensitive config
- [ ] `deploy/k8s/secret.yaml` — secret template
- [ ] `deploy/docker-compose.yml` — local dev (OpenResty + PostgreSQL)

### Task 14: Documentation

- [ ] `README.md` — project overview, quick start, architecture summary
- [ ] `docs/api.md` — API reference (all endpoints with request/response examples)
- [ ] `docs/deployment.md` — Docker/K8s deployment guide
- [ ] `docs/development.md` — local development setup guide
