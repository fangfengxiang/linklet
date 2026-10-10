## ADDED Requirements

### Requirement: PostgreSQL connection pool

The system SHALL use pgmoon's PostgresPool for coroutine-safe PostgreSQL connection management.

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
- **THEN** the handler SHALL access parameters via ctx.request.params
