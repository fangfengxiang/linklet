## Design

### Architecture Overview

Linklet follows a layered architecture with explicit dependency injection:

```
HTTP Request
    ↓
Nginx (conf.d/default.conf)
    ↓
Router (src/router.lua) — route matching, middleware chain
    ↓
Middleware Chain
    ├── auth.lua (AK/SK verification, tenant extraction)
    ├── validate.lua (request parameter validation)
    └── json.lua (request body JSON parsing)
    ↓
Handler
    ├── shorten/handler.lua (create/gen/disable)
    ├── shorten/cache_handler.lua (cache lookup)
    ├── shorten/resolve_handler.lua (DB query, status check, cache write)
    └── shorten/redirect_handler.lua (HTTP 302)
    ↓
Model Layer (src/models/)
    ├── link.lua (sl_link CRUD)
    ├── tenant.lua (sl_tenant)
    ├── tenant_credential.lua (AK/SK)
    ├── scene.lua (sl_scene)
    └── domain_entry.lua (sl_domain_entry)
    ↓
Infrastructure (src/lib/)
    ├── database.lua (pgmoon pool wrapper)
    ├── cache.lua (ngx.shared.DICT wrapper)
    ├── request.lua (HTTP request utilities)
    └── response.lua (JSON response utilities)
```

### Module Design

#### Short Code Generation (src/lib/obfuscator.lua)

```lua
local _M = {}
_M.__index = _M

local GOLDEN_RATIO = 0x9E377B97F4A7C15  -- (√5-1)/2 × 2^64
local BASE_OFFSET = 916132832           -- 62^5, ensures ≥6 chars
local BASE62_CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

function _M.obfuscate(id)
    -- Golden ratio multiplication + segment mixing
end

function _M.encode_base62(num)
    -- Standard Base62 encoding
end

function _M.generate(id)
    return _M.encode_base62(_M.obfuscate(id))
end
```

**Collision fix**: The original algorithm truncates to high 32 bits, losing information. The fix: use full 64-bit multiplication result, or use a modular hash function that preserves bijection within the ID space.

#### ID Generator (src/lib/id_generator.lua)

```lua
local _M = {}
_M.__index = _M

function _M.new(opts)
    -- opts: { db, segment_size (default 1000) }
end

function _M:next_id()
    -- If local segment exhausted, allocate new segment from PostgreSQL
    -- Atomic UPDATE ... RETURNING for segment reservation
end
```

**PostgreSQL segment allocation**:
```sql
UPDATE sl_id_sequence
SET current_max = current_max + $1
RETURNING current_max - $1 AS segment_start, current_max AS segment_end;
```

#### Resolution Flow

Cache-first resolution with three handlers composed as middleware:

```
GET /:code
    ↓
CacheHandler (ngx.shared.DICT lookup)
    ├── HIT → set ctx.target_url, skip to RedirectHandler
    └── MISS → next()
                ↓
        ResolveHandler (DB query)
            ├── Found + valid → set ctx.target_url, write cache, next()
            ├── Found + disabled → return 410
            ├── Found + expired → return 410
            └── Not found → return 404
                ↓
        RedirectHandler (302)
```

### Key Design Decisions

1. **No web framework**: OpenResty native `content_by_lua` + custom router. No Lapis, no Gorilla, no middleware framework.

2. **Explicit DI**: All dependencies passed via constructor params. No `ngx.ctx` as service locator.

3. **pgmoon connection pool**: `pgmoon.pool.PostgresPool` is coroutine-safe. Each `db:query` gets its own connection from the pool.

4. **Model layer without ORM**: Simple table-based models with `query(sql, ...)` pattern. No Lapis model ORM, no ActiveRecord.

5. **Status integers**: 1=active, 2=disabled. Logical delete via separate field (deleted_at or status=deleted). Terminal states cannot be reversed.

6. **Unified JSON response**: All management API responses use `{code, message, data}` format.

### Database Schema

```sql
CREATE TABLE sl_tenant (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(255) NOT NULL,
    scene_ids   BIGINT[] DEFAULT '{}',
    status      SMALLINT DEFAULT 1,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE sl_domain_entry (
    id          BIGSERIAL PRIMARY KEY,
    tenant_id   BIGINT REFERENCES sl_tenant(id),
    domain      VARCHAR(255) NOT NULL UNIQUE,
    label       VARCHAR(255),
    description TEXT,
    status      SMALLINT DEFAULT 1,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW(),
    enabled_at  TIMESTAMPTZ,
    disabled_at TIMESTAMPTZ,
    deleted_at  TIMESTAMPTZ
);

CREATE TABLE sl_scene (
    scene_id        BIGSERIAL PRIMARY KEY,
    tenant_id       BIGINT REFERENCES sl_tenant(id),
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    domain_entry_id BIGINT REFERENCES sl_domain_entry(id),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE sl_scene_config (
    id          BIGSERIAL PRIMARY KEY,
    scene_id    BIGINT REFERENCES sl_scene(scene_id),
    config_key  VARCHAR(255) NOT NULL,
    config_value TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(scene_id, config_key)
);

CREATE TABLE sl_link (
    id          BIGSERIAL PRIMARY KEY,
    code        VARCHAR(20) NOT NULL UNIQUE,
    target_url  TEXT NOT NULL,
    scene_id    BIGINT NOT NULL REFERENCES sl_scene(scene_id),
    status      SMALLINT NOT NULL DEFAULT 1,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    expires_at  TIMESTAMPTZ
);

CREATE TABLE sl_id_sequence (
    id          BIGINT PRIMARY KEY DEFAULT 1,
    current_max BIGINT NOT NULL DEFAULT 0
);

INSERT INTO sl_id_sequence (id, current_max) VALUES (1, 0) ON CONFLICT DO NOTHING;
```

### Nginx Configuration

```nginx
lua_shared_dict linklet_cache 10m;

server {
    listen 80;
    server_name _;

    # Resolution gateway
    location ~ ^/(.+)$ {
        content_by_lua_file /app/src/app.lua;
    }

    # Management API
    location /shorten/ {
        limit_except POST { deny all; }
        content_by_lua_file /app/src/app.lua;
    }

    location /admin/ {
        content_by_lua_file /app/src/app.lua;
    }

    location /v1/ {
        content_by_lua_file /app/src/app.lua;
    }
}
```

### Testing Strategy

- **Unit tests** (`spec/`): busted BDD, cover algorithm + model logic
- **Functional tests** (`spec/`): API integration with mocked DB
- **E2E tests** (`test/e2e/`): Full flow with Docker (OpenResty + PostgreSQL)
- **Benchmark** (`test/benchmark/`): Short code generation throughput
- **Coverage**: luacov, threshold 80%

### CI/CD Pipeline

```yaml
# .github/workflows/test.yml
jobs:
  test:
    matrix: [lua 5.1, luajit-2.1, lua 5.3]
    steps:
      - luacheck src/ spec/
      - busted --coverage
      - luacov
      - coverage-threshold.sh 80
  
  e2e:
    needs: [test]
    steps:
      - docker build
      - docker run (OpenResty + PostgreSQL)
      - busted test/e2e/
```
