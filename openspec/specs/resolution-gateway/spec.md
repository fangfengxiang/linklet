# resolution-gateway Specification

## Purpose

Resolve active links using deadline-aware caching and bounded cross-instance invalidation.

## Requirements

### Requirement: Cache-first resolution

The system SHALL check the cache (ngx.shared.DICT) before querying the database for short code resolution.

#### Scenario: Cache hit

- **GIVEN** a short code "aB9xK2" exists in the cache with target URL "https://example.com/page"
- **WHEN** a GET request for "/aB9xK2" is received
- **THEN** the system SHALL return HTTP 302 with Location header set to the cached target URL
- **AND** the system SHALL NOT query the database

#### Scenario: Cache miss with valid link

- **GIVEN** a short code "aB9xK2" is NOT in the cache but exists in the database
- **WHEN** a GET request for "/aB9xK2" is received
- **THEN** the system SHALL query the database for the link record
- **AND** the system SHALL write the resolution result to the cache
- **AND** the system SHALL return HTTP 302 with the target URL

#### Scenario: Cache miss with non-existent code

- **GIVEN** a short code "zzzzzz" does NOT exist in the cache or database
- **WHEN** a GET request for "/zzzzzz" is received
- **THEN** the system SHALL return HTTP 404

### Requirement: Link status validation

The system SHALL validate link status and expiration before redirecting.

#### Scenario: Active link

- **GIVEN** a link with status=1 (active) and no expiration
- **WHEN** the code is resolved
- **THEN** the system SHALL redirect to the target URL

#### Scenario: Disabled link

- **GIVEN** a link with status=2 (disabled)
- **WHEN** the code is resolved
- **THEN** the system SHALL return HTTP 404 or 410 (Gone)

#### Scenario: Expired link

- **GIVEN** a link with expires_at in the past
- **WHEN** the code is resolved
- **THEN** the system SHALL return HTTP 410 (Gone)

### Requirement: Cache invalidation on status change

The system SHALL invalidate the cache entry when a link is disabled or deleted.

#### Scenario: Disable link invalidates cache

- **GIVEN** a link "aB9xK2" is cached with status=1 (active)
- **WHEN** the link is disabled via management API
- **THEN** the cache entry for "aB9xK2" SHALL be removed
- **AND** subsequent resolution in that instance SHALL return HTTP 404/410

### Requirement: Redirect response

The system SHALL return HTTP 302 redirect for valid short codes.

#### Scenario: Successful redirect

- **GIVEN** a valid active link with target_url "https://example.com/page"
- **WHEN** the short code is resolved
- **THEN** the response SHALL have status code 302
- **AND** the response SHALL have a Location header with the target URL

### Requirement: Business deadline and cross-instance invalidation

Cache TTL SHALL not exceed the link lifetime. Independent instances SHALL use durable revision synchronization and bypass stale caches.

#### Scenario: Warm cache reaches the link deadline

- **GIVEN** a link expires in 0.5 seconds and configured cache TTL is 300 seconds
- **WHEN** it is resolved, cached, and requested after its deadline
- **THEN** the response SHALL be 410

#### Scenario: Lookup races a local disable

- **GIVEN** a database lookup reads an active link and yields before writing cache
- **WHEN** the same instance disables that link
- **THEN** the old lookup SHALL NOT restore its cache entry

#### Scenario: Independent instance caches

- **GIVEN** two independent caches contain the same link
- **WHEN** one instance disables it and the other synchronizes the durable revision
- **THEN** the second cache SHALL be invalidated
- **AND** with the default 0.5-second poll, synchronization older than 1 second SHALL bypass cache

### Requirement: Effective link resolution
Gateway SHALL 根据请求 Host+Code、短链启用状态、expires_at、当前 DomainEntry 状态判定是否跳转；Tenant/Scene 停用 SHALL NOT 使既有有效短链失效。
#### Scenario: Disabled scene but active link
- **GIVEN** Scene 停用但 ShortLink 启用、未过期且域名投产
- **WHEN** 请求匹配 Host+Code
- **THEN** Gateway SHALL 返回 302
#### Scenario: Host mismatch
- **GIVEN** 短链 Scene 当前绑定 domain-a
- **WHEN** 请求使用 domain-b 和同一 code
- **THEN** Gateway SHALL NOT 重定向到目标地址
### Requirement: Unified cached resolution
缓存命中与数据库命中 SHALL 返回一致的解析结果，再统一由 Redirect 输出；缓存 SHALL 不直接发送 302。
#### Scenario: Disabled link invalidation
- **GIVEN** 某 code 已缓存
- **WHEN** 管理接口停用它并完成失效传播
- **THEN** 后续解析 SHALL 不再跳转
