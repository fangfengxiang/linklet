# Linklet

> A multi-tenant short link system built on OpenResty + Lua + PostgreSQL.

[![Test](https://github.com/frank/linklet/actions/workflows/test.yml/badge.svg)](https://github.com/frank/linklet/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

Linklet is a self-hosted short link service that provides:

- **Short code generation** — Golden ratio obfuscation + Base62 encoding (≥6 chars, non-predictable)
- **Segment-based ID allocation** — PostgreSQL batch allocation, worker-local consumption
- **Cache-first resolution** — `ngx.shared.DICT` → PostgreSQL → HTTP 302 redirect
- **Management API** — Create / generate / disable short links with unified JSON response
- **Multi-tenant auth** — AK/SK + HMAC signature, encrypted SK storage
- **Scene-based domain management** — Link → Scene → Domain Entry → Tenant isolation chain

## Architecture

```
HTTP Request
    ↓
Nginx (OpenResty)
    ↓
Router → Middleware Chain (auth, validate, json)
    ↓
Handler (shorten/handler, cache_handler, resolve_handler, redirect_handler)
    ↓
Model Layer (link, scene, domain_entry, tenant, tenant_credential)
    ↓
Infrastructure (pgmoon pool, ngx.shared.DICT cache)
```

### Core Modules

| Module | File | Responsibility |
|--------|------|----------------|
| Obfuscator | `src/lib/obfuscator.lua` | Golden ratio obfuscation + Base62 encoding |
| ID Generator | `src/lib/id_generator.lua` | Segment-based ID allocation from PostgreSQL |
| Database | `src/lib/database.lua` | pgmoon connection pool wrapper |
| Cache | `src/lib/cache.lua` | ngx.shared.DICT wrapper |
| Router | `src/router.lua` | Route matching + middleware chain |
| Auth | `src/middleware/auth.lua` | AK/SK HMAC verification |
| Handler | `src/shorten/handler.lua` | Create / gen / disable endpoints |
| Resolve | `src/shorten/resolve_handler.lua` | DB query + status/expiry validation + cache write |

## Quick Start

### Prerequisites

- OpenResty 1.21+ (or Nginx + LuaJIT)
- PostgreSQL 12+
- LuaRocks

### Install

```bash
luarocks make --local
```

### Database Setup

```bash
psql -U postgres -f migrations/001_init.sql
```

### Run with Docker

```bash
docker compose -f deploy/docker-compose.yml up -d
curl http://localhost:8080/health
```

### Development

```bash
# Install test dependencies
luarocks install busted --local
luarocks install luacov --local
luarocks install luacheck --local

# Run tests
busted spec/

# Run lint
luacheck src/ spec/

# Run benchmark
lua test/benchmark/obfuscator_bench.lua
```

## API Reference

### Resolution Gateway

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/:code` | Resolve short code and 302 redirect |

### Management API

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/shorten/create` | Create short link |
| `POST` | `/shorten/gen` | Create short link with full URL |
| `PUT` | `/shorten/disable` | Disable short link |

### Request Example

```bash
curl -X POST http://localhost:8080/shorten/create \
  -H "Content-Type: application/json" \
  -H "X-Access-Key: your-ak" \
  -H "X-Signature: your-signature" \
  -H "X-Timestamp: 1697000000" \
  -d '{"target_url":"https://example.com/page","scene_id":1}'
```

### Response Format

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "code": "aB9xK2"
  }
}
```

## Testing

| Type | Tool | Location | Coverage |
|------|------|----------|----------|
| Unit (BDD) | busted | `spec/` | Algorithm, models, handlers, middleware |
| E2E | busted | `test/e2e/` | Full resolution flow |
| Benchmark | lua | `test/benchmark/` | Code generation throughput |
| Lint | luacheck | — | src/ + spec/ |

### CI/CD Pipeline

- **test.yml** — luacheck + busted + luacov coverage (Lua 5.1, LuaJIT 2.1, Lua 5.3)
- **benchmark.yml** — Benchmark on PR
- **release.yml** — Tag-triggered Docker image build + GHCR push

## Project Structure

```
linklet/
├── src/
│   ├── app.lua              # Entry point
│   ├── router.lua           # Route matching + middleware chain
│   ├── routes.lua           # Route definitions
│   ├── lib/                 # Infrastructure
│   ├── middleware/          # Auth, validate, JSON
│   ├── shorten/             # Handlers
│   └── models/              # Data access layer
├── spec/                    # BDD unit tests
├── test/                    # E2E + benchmark
├── conf/                    # Nginx configuration
├── migrations/              # SQL migrations
├── deploy/                  # Docker + K8s
├── docs/                    # Design docs + ADR
├── .github/workflows/       # CI/CD
├── Dockerfile
├── Makefile
└── linklet-scm-1.rockspec
```

## Design Decisions

See `docs/design.md` for the full design document and `docs/adr.md` for the architecture decision record index.

### Key Decisions

1. **OpenResty native** — No extra web framework, leverage Nginx + Lua directly
2. **Explicit DI** — Dependencies via constructor params, no Context as service locator
3. **Cache-first** — Resolution path checks cache before database
4. **Golden ratio obfuscation** — Non-predictable short codes with collision-free guarantee
5. **Segment-based ID allocation** — Reduce DB access with batch segment allocation
6. **Irreversible status** — Disabled/deleted links cannot be re-enabled

## License

MIT
