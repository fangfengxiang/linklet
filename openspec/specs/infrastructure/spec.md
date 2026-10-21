# infrastructure Specification

## Purpose

Provide pooled database access, cache primitives, routing and consistent request/response behavior.

## Requirements

### Requirement: PostgreSQL connection pool

The system SHALL use pgmoon's OpenResty cosocket keepalive pool for coroutine-safe PostgreSQL connection management.

#### Scenario: Concurrent queries from different coroutines

- **GIVEN** multiple OpenResty worker coroutines need database access
- **WHEN** they call db:query simultaneously
- **THEN** each coroutine SHALL get its own connection from the pool
- **AND** connections SHALL be returned to the pool after use

#### Scenario: Pool size configuration

- **GIVEN** a database configuration with max_pool_size=10
- **WHEN** the database object is created
- **THEN** the connection pool SHALL have a maximum of 10 connections

### Requirement: Nginx shared dictionary cache

The system SHALL use ngx.shared.DICT for inter-worker cache sharing.

#### Scenario: Cache is shared across workers

- **GIVEN** worker A writes a cache entry for code "aB9xK2"
- **WHEN** worker B receives a request for "/aB9xK2"
- **THEN** worker B SHALL find the cache entry written by worker A

#### Scenario: Cache TTL expiration

- **GIVEN** a cache entry with TTL=300 seconds
- **WHEN** 300 seconds have passed since the entry was written
- **THEN** the cache entry SHALL be expired
- **AND** subsequent lookups SHALL return nil

### Requirement: Router with middleware chain

The system SHALL implement a router that dispatches requests through a middleware chain to handlers.

#### Scenario: Request matches a route

- **GIVEN** a route GET /:code is registered
- **WHEN** a GET /aB9xK2 request is received
- **THEN** the router SHALL match the route
- **AND** the request SHALL pass through registered middleware before reaching the handler

#### Scenario: Middleware chain execution

- **GIVEN** middleware [auth, validate] and handler [resolve] are registered for a route
- **WHEN** a request matches the route
- **THEN** the middleware SHALL execute in order: auth → validate → resolve
- **AND** each middleware SHALL be able to short-circuit the chain

### Requirement: Unified request/response utilities

The system SHALL provide request and response utility modules for consistent HTTP handling.

#### Scenario: JSON response helper

- **GIVEN** a handler needs to return JSON data
- **WHEN** the handler calls response:json(status_code, body_table)
- **THEN** the response SHALL have the specified HTTP status code
- **AND** the response body SHALL be JSON-encoded
- **AND** the Content-Type header SHALL be "application/json"

#### Scenario: Request parameter parsing

- **GIVEN** a POST request with JSON body
- **WHEN** the request utility parses the body
- **THEN** the handler SHALL access parameters via ctx.params after JSON parsing and endpoint validation

### Requirement: Transaction failure and health semantics

Transactions SHALL roll back exceptions and nil/false callback results. Readiness SHALL check PostgreSQL.

#### Scenario: Callback returns a failure

- **GIVEN** an insert executed inside a transaction
- **WHEN** the callback returns nil and an error
- **THEN** the insert SHALL be rolled back and the error SHALL propagate

#### Scenario: Database unavailable

- **GIVEN** PostgreSQL cannot be queried
- **WHEN** /health is requested
- **THEN** the response SHALL be 503 while /health/live SHALL remain 200

### Requirement: Lua module boundaries
系统 SHALL 以 `lib/linklet/` 为 Lua 模块根目录；Admin 与 Gateway SHALL 不互相依赖；Core SHALL 不直接访问 ngx/HTTP 请求或 SQL；Repository SHALL 封装 SQL；Core SHALL 返回领域错误，由 Admin 映射为 HTTP 状态及响应码。
#### Scenario: Core standalone tests
- **GIVEN** 无 OpenResty 运行环境
- **WHEN** 执行纯 Core 单元测试
- **THEN** 测试 SHALL 能使用注入的 Repository 替身运行
### Requirement: Safe incremental migration
已部署数据库 SHALL 使用增量迁移，保留原 code、group_id、current_max、AK；旧 active 域名状态 SHALL 正确映射到新 deployed。
#### Scenario: No sequence reset
- **GIVEN** 生产数据库已有短码
- **WHEN** 运行迁移
- **THEN** 发号状态 SHALL 不重置，短码集合 SHALL 不丢失
