# Linklet core implementation design

## Scope and decisions

OpenResty + LuaJIT + PostgreSQL, explicit constructor dependencies, no web framework or ORM.
Canonical APIs are `/api/v1/shorten/create`, `/api/v1/shorten/gen`, `/api/v1/shorten/disable` and `/api/v1/admin/*`.
Five domain tables plus credentials and ID sequence give seven physical tables.

## Short codes and segments

The user selected the 32-bit ID capacity on 2026-10-13: positive IDs 1..4294967295.
`(id * 2654435769) mod 2^32 + 62^5` is computed with two 16-bit limbs, keeping intermediate values exact in LuaJIT.
Base62 uses `0-9a-zA-Z` and codes have at least six characters. The permutation is reversible and is not an access-control secret.
Existing stored codes continue to resolve; no code rewrite or sequence reset occurs during deployment.

A reservation adds the configurable segment size atomically and returns the inclusive interval `[old_max+1,new_max]`.
A worker-local semaphore serializes reservations while coroutine I/O yields; the fast path consumes IDs without database access.
The reservation refuses a segment crossing the 32-bit boundary. Unused IDs are never recovered after restart.

## Request processing and authentication

Nginx locations route requests through auth → JSON → endpoint-specific validation → handler.
Auth signs `METHOD\nREQUEST_URI\nTIMESTAMP\nRAW_BODY`; REQUEST_URI includes the original query string.
Timestamp is mandatory and must be within 300 seconds. Repeated valid requests within that window are not exactly-once operations.
Body data is read from memory or the Nginx body file before signature verification. Only JSON objects are accepted.
Credential lookup also requires an active tenant. OpenSSL CRYPTO_memcmp compares signatures in OpenResty.

SKs use AES-256-GCM with independent random 12-byte nonces, a 16-byte authentication tag and versioned Base64 envelopes.
A mandatory deployment key contains 64 hexadecimal characters. Ciphertext corruption and unversioned legacy XOR records fail closed.
New AK and SK values come from OpenSSL strong randomness. Legacy credentials must be reissued, not silently decoded with a public fallback key.

## Models and management

Links contain only scene_id. Scenes provide tenant ownership; a composite foreign key guarantees scene and domain owners agree.
Create/gen validate scene ownership. Gen also requires an active domain and returns an HTTP(S) URL.
Disable performs a single tenant-constrained UPDATE and returns 404 for an unavailable link, including another tenant's code.
Validation errors are 400, authentication errors 401, foreign scene errors 403; errors include JSON data:null.
Database errors are distinguished from missing records and are not converted to 404.

Migration 003 adds status checks, terminal-state triggers, immutable domain/link guards and permanent code retention.
Terminal statuses cannot transition backward. Domain status can advance from active to disabled to deleted.

## Resolution and consistency

CacheHandler → ResolveHandler → RedirectHandler uses ngx.shared.DICT for inter-worker cache sharing.
The database returns expiry as EXTRACT(EPOCH FROM expires_at); cache TTL is min(configured TTL, remaining lifetime).
Expired links return 410 on both cold and warm paths. Missing links return 404; disabled links/entities return 410.
A shared generation counter prevents an in-flight old lookup from restoring a locally invalidated cache entry.

Independent instances poll `sl_id_sequence.cache_revision` in one worker-0 timer per instance.
Transactional status triggers advance the durable revision. A changed revision flushes positive cache entries and advances the local generation.
Default polling is 0.5 seconds; cached data is used only while a successful revision check is at most 1 second old.
If polling stalls or the database becomes unavailable, stale cache entries are bypassed. This defines bounded propagation, not synchronous global invalidation.

## Database connections

pgmoon.new receives the configuration directly. Every query/coroutine obtains its own connection object.
Connections are returned using pgmoon:keepalive to the OpenResty cosocket pool, with pool_size/backlog and timeouts.
SQL scalar values use escape_literal. Raw statements and decrypted secrets are not logged.
Transactions roll back exceptions and nil/false callback results; BEGIN and COMMIT failures propagate.

## Deployment and testing

Nginx explicitly preserves database and encryption environment variables and starts cache synchronization in init_worker.
`/health` checks PostgreSQL readiness; `/health/live` checks process liveness.
Admin locations allow loopback by default; deployments must configure narrowly scoped trusted administration access.
Docker has dependency, runtime and acceptance stages; development Compose does not seed data or reset IDs at startup.
Kubernetes separates Deployment/Service, ConfigMap and Secret templates; migration is a deliberate deployment step.

Test::Nginx executes actual HTTP against the production locations and pgmoon against a disposable PostgreSQL database.
Seven test files cover IDs, management, resolution, auth/crypto, database/models, admin/runtime and production initialization.
LuaCov combines normalized unit and OpenResty source paths. The combined source coverage threshold is 80%.
CI propagates all test failures; the Docker acceptance job requires lint and the Lua 5.1/5.3/LuaJIT unit matrix.

## Rollback

Apply 001 and 003 once to fresh databases; only apply 003 to existing 001 installations after checking current data.
Verify 003_down then 001_down in a disposable database. Do not use DROP-table rollback on live data.
Keep backups and coordinate runtime/schema rollback. Old code cannot read AES-GCM credentials, so rolling back code alone after credential rotation is not compatible.
