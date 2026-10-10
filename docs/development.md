# Development Guide

## Prerequisites

- Lua 5.1 / LuaJIT 2.1 / Lua 5.3+
- LuaRocks 3.x
- PostgreSQL 12+
- busted, luacov, luacheck (via LuaRocks)

## Setup

```bash
# Clone the repository
git clone https://github.com/frank/linklet.git
cd linklet

# Install dependencies
luarocks install busted --local
luarocks install luacov --local
luarocks install luacheck --local
luarocks install lua-cjson --local
luarocks install pgmoon --local

# Set up database (local PostgreSQL)
createdb linklet
psql -d linklet -f migrations/001_init.sql
```

## Running Tests

### Unit Tests (BDD)

```bash
busted spec/
```

### Lint

```bash
luacheck src/ spec/
```

### Coverage

```bash
busted spec/ -c "luacov"
luacov src/
cat luacov.report.out
```

Coverage threshold: 80%

### Benchmark

```bash
export LUA_PATH="src/?.lua;;"
lua test/benchmark/obfuscator_bench.lua
```

## Project Structure

```
src/
├── app.lua                 # Application entry point
├── router.lua              # Route matching + middleware chain
├── routes.lua              # Route definitions
├── lib/
│   ├── database.lua        # pgmoon connection pool
│   ├── cache.lua           # ngx.shared.DICT wrapper
│   ├── request.lua         # HTTP request utilities
│   ├── response.lua        # HTTP response utilities
│   ├── obfuscator.lua      # Golden ratio + Base62
│   └── id_generator.lua    # Segment-based ID allocation
├── middleware/
│   ├── json.lua            # JSON body parsing
│   ├── validate.lua        # Parameter validation
│   └── auth.lua            # AK/SK HMAC auth
├── shorten/
│   ├── handler.lua         # Create/gen/disable
│   ├── cache_handler.lua   # Cache lookup
│   ├── resolve_handler.lua # DB query + validation
│   └── redirect_handler.lua # HTTP 302
└── models/
    ├── base_model.lua      # Shared query execution
    ├── link.lua            # sl_link
    ├── tenant.lua          # sl_tenant
    ├── tenant_credential.lua # AK/SK
    ├── scene.lua           # sl_scene
    └── domain_entry.lua    # sl_domain_entry
```

## Adding a New Endpoint

1. Add route in `src/routes.lua`
2. Implement handler in `src/shorten/handler.lua`
3. Add model method if needed in `src/models/`
4. Write tests in `spec/`
5. Run `luacheck src/ spec/` and `busted spec/`

## Docker Development

```bash
# Start full stack
docker compose -f deploy/docker-compose.yml up -d

# View logs
docker compose -f deploy/docker-compose.yml logs -f

# Run tests in container
docker exec -it linklet busted spec/

# Cleanup
docker compose -f deploy/docker-compose.yml down -v
```
