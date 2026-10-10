# API Reference

## Resolution Gateway

### `GET /:code`

Resolve a short code and redirect to the target URL.

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

- First request: cache miss → database query → cache write → 302 redirect
- Subsequent requests: cache hit → skip database → 302 redirect
- Cache TTL: 300 seconds (configurable)
- Cache invalidation: automatic on link disable

---

## Management API

All management API endpoints require AK/SK authentication headers:

| Header | Description |
|--------|-------------|
| `X-Access-Key` | Access key identifier |
| `X-Signature` | HMAC-SHA1 signature |
| `X-Timestamp` | Request timestamp (Unix epoch, ±5 min window) |

### `POST /shorten/create`

Create a short link. Returns the generated short code.

**Request Body**

```json
{
  "target_url": "https://example.com/page",
  "scene_id": 1,
  "expires_at": "2025-12-31T23:59:59Z"
}
```

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `target_url` | Yes | string | Target URL (max 2048 chars) |
| `scene_id` | Yes | number | Scene ID |
| `expires_at` | No | string | Expiration timestamp (ISO 8601) |

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
| 400 | 4002 | scene_id is required |
| 403 | 4004 | scene does not belong to tenant |
| 404 | 4003 | scene not found or inactive |
| 500 | 500 | internal server error |

### `POST /shorten/gen`

Create a short link and return the full short URL (domain + code).

**Request Body** — Same as `/shorten/create`

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
| 400 | 4005 | domain not configured for scene |

### `PUT /shorten/disable`

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
{METHOD}\n{URI}\n{TIMESTAMP}\n{BODY}
```

- `METHOD`: HTTP method (GET, POST, PUT, DELETE)
- `URI`: Request path (e.g., `/shorten/create`)
- `TIMESTAMP`: Unix epoch from `X-Timestamp` header
- `BODY`: Raw request body (JSON string)

The HMAC key is the decrypted Secret Key (SK).

### SK Storage

- SK is stored encrypted in the database (`secret_key_enc` column)
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
