# API Reference

## Resolution Gateway

### `GET /:code`

Resolve a short code under the Group current deployed domain. Host mismatch returns 404. Tenant/Group status does not block existing links.

**Request**

```
GET /aB9xK2
```

**Responses**

| Status | Condition | Body |
|--------|-----------|------|
| `302` | Active link found | `Location: <target_url>` header, empty body |
| `404` | Short code not found | `{"code":404,"message":"not found","data":null}` |
| `410` | Link disabled or expired | `{"code":410,"message":"link disabled","data":null}` |

**Cache Behavior**

- Cache key includes normalized Host + Code + generation.
- First request: cache miss → database query → cache write → 302 redirect
- Subsequent requests: cache hit → skip database → 302 redirect
- Cache TTL: min(300 seconds by default, remaining link lifetime)
- Cache invalidation: immediate within the instance; independent instances synchronize durable revisions (default freshness window: 1 second). Stale synchronization bypasses cache.

---

## Management API

All management API endpoints require AK/SK authentication headers:

| Header | Description |
|--------|-------------|
| `X-Access-Key` | Access key identifier |
| `X-Signature` | HMAC-SHA1 signature |
| `X-Timestamp` | Request timestamp (Unix epoch, ±5 min window) |

### `POST /api/v1/shorten/create`

Create a short link. Returns the generated short code.

**Request Body**

```json
{
  "target_url": "https://example.com/page",
  "group_id": 1,
  "expires_at": "2099-12-31T23:59:59Z"
}
```

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `target_url` | Yes | string | Target URL (max 2048 chars) |
| `group_id` | Yes | number | Group business ID (1..4294967295) |
| `expires_at` | No | string | Future RFC3339 timestamp; omitted or null = permanent |

**Response**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "code": "aB9xK2"
  }
}
```

**Errors**

| HTTP | Error Code | Message |
|------|------------|---------|
| 400 | 4001 | target_url is required |
| 400 | 4002 | group_id is required |
| 403 | 4004 | group not authorized |
| 404 | 4003 | group not found or inactive |
| 500 | 500 | internal server error |

### `POST /api/v1/shorten/gen`

Create a short link and return the full short URL (domain + code).

**Request Body** — Same as `/api/v1/shorten/create`

**Response**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "code": "aB9xK2",
    "short_url": "https://s.example.com/aB9xK2"
  }
}
```

**Additional Errors**

| HTTP | Error Code | Message |
|------|------------|---------|
| 400 | 4005 | domain not configured for group |

### `PUT /api/v1/shorten/disable`

Disable a short link. This operation is irreversible — disabled links cannot be re-enabled.

**Request Body**

```json
{
  "code": "aB9xK2"
}
```

**Response**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "code": "aB9xK2",
    "status": "disabled"
  }
}
```

**Errors**

| HTTP | Error Code | Message |
|------|------------|---------|
| 400 | 4001 | code is required |
| 404 | 4006 | link not found or already disabled |

---

## Authentication

### AK/SK Signature

The signature is computed as HMAC-SHA1 of the following string:

```
{METHOD}\n{REQUEST_URI}\n{TIMESTAMP}\n{BODY}
```

- `METHOD`: HTTP method (GET, POST, PUT, DELETE)
- `REQUEST_URI`: Raw request path and query string (e.g., `/api/v1/shorten/create?group_id=1`)
- `TIMESTAMP`: Unix epoch from `X-Timestamp` header
- `BODY`: Raw request body (JSON string)

The HMAC key is the decrypted Secret Key (SK).

### SK Storage

- SK uses versioned AES-256-GCM envelopes with random nonces in `secret_key_enc`. `LINKLET_ENCRYPTION_KEY` must be 64 hexadecimal characters. Legacy XOR credentials must be reissued.
- SK is decrypted on-demand for signature verification only
- Decrypted SK is never logged or cached

---

## Unified Response Format

All management API responses follow this structure:

### Success

```json
{
  "code": 0,
  "message": "success",
  "data": { ... }
}
```

### Error

```json
{
  "code": <non-zero error code>,
  "message": "<error description>",
  "data": null
}
```

## Administration and health

Admin endpoints are loopback-only by default and use the same JSON response format:

| Method | Path | JSON body / parameters |
|---|---|---|
| POST | `/api/v1/admin/tenant/create` | `{"name":"tenant"}` |
| GET | `/api/v1/admin/tenant/list` | optional `limit` query parameter |
| POST | `/api/v1/admin/credential/create` | `{"tenant_id":1}`; optional access_key/secret_key |
| PUT | `/api/v1/admin/credential/disable` | `{"access_key":"..."}` |

Generated AK/SK values use cryptographic randomness. A custom SK must contain 16–256 characters. The plaintext SK is returned only when creating the credential.

`GET /health` returns 200 when PostgreSQL responds, or 503 otherwise. `GET /health/live` returns 200 while the process serves requests.

Only JSON objects are accepted for write requests. Timestamp is mandatory. Sign the exact query and body bytes; a valid request can still be replayed within the 300-second window, so clients must not assume exactly-once execution.

### Signing example

```python
import base64, hashlib, hmac, time
method = "POST"
uri = "/api/v1/shorten/create"
body = '{"target_url":"https://example.com/page","group_id":1}'
timestamp = str(int(time.time()))
message = "\n".join([method, uri, timestamp, body]).encode()
signature = base64.b64encode(hmac.new(secret_key.encode(), message, hashlib.sha1).digest()).decode()
```

## v0.2 operator resources

The full machine-readable contract is [api/openapi.yaml](../api/openapi.yaml). All paths below begin with `/api/v1/admin/` and retain the loopback-only network policy. They do not implement browser sessions; do not persist SK in a browser.

| Method | Resource/action | Parameters |
|---|---|---|
| PUT | tenant/grant | id, group_ids array (deduplicated; all groups must exist) |
| PUT | tenant/status | id, status 1/2 |
| POST | domain/create | domain hostname; optional tag, description |
| GET | domain/list | none; first 100 |
| PUT | domain/deploy, domain/disable | id; new→deployed→offline, bound groups prevent offline |
| POST | group/create | group_id, name, domain_entry_id |
| GET | group/list | tenant_id query, authorized groups |
| PUT | group/configure | group_id; domain_entry_id and/or status 1/2; domain changes require no links |
| PUT | group_config/set | group_id, config_key, config_value; optional description |
| GET | group_config/list | group_id query |
| DELETE | group_config/delete | group_id, config_key JSON body |

`GET /api/v1/shorten/get?code=...` requires AK/SK headers and current Group authorization. Unauthorized/missing links return 404. Two tenants granted the same Group may create, read and disable its links. Revocation affects future management operations, never historical redirects.

Both create and gen require a deployed domain. Bad expiration is 400; creation requires a future timestamp, while existing expired records resolve to 410. Domain state conflicts are 409. Rebinding a Group with any links (including disabled/expired links) returns 409; release implications are documented in [the migration guide](v02-migration.md). GroupConfig is a KV store; parameter forwarding is not yet implemented.
