## ADDED Requirements

### Requirement: BDD unit tests with busted

The system SHALL have unit tests written in BDD style using the busted framework.

#### Scenario: Test coverage for short code generation

- **GIVEN** the short code generation module is implemented
- **WHEN** `busted spec/` is executed
- **THEN** tests for code generation, Base62 encoding, and collision detection SHALL pass

#### Scenario: Coverage threshold enforcement

- **GIVEN** all unit tests pass
- **WHEN** luacov generates the coverage report
- **THEN** the combined unit and real OpenResty source coverage SHALL meet or exceed 80%

### Requirement: LuaRocks package

The system SHALL be packaged as a LuaRocks rockspec for dependency management.

#### Scenario: Rockspec builds successfully

- **GIVEN** the rockspec file is valid
- **WHEN** `luarocks make --local` is executed
- **THEN** all modules SHALL be installed
- **AND** `require("linklet")` SHALL succeed

### Requirement: Luacheck linting

The system SHALL pass luacheck linting with zero errors.

#### Scenario: No lint errors in source

- **GIVEN** all source files are written
- **WHEN** `luacheck src/ spec/` is executed
- **THEN** the exit code SHALL be 0
- **AND** there SHALL be no warnings or errors

### Requirement: GitHub Actions CI pipeline

The system SHALL have a GitHub Actions CI pipeline that runs lint, tests, and coverage on every push and pull request.

#### Scenario: CI runs on push

- **GIVEN** code is pushed to any branch
- **WHEN** the GitHub Actions workflow triggers
- **THEN** luacheck SHALL run on src/ and spec/
- **AND** busted tests SHALL run with coverage
- **AND** luacov coverage report SHALL be generated

#### Scenario: CI runs on pull request

- **GIVEN** a pull request is opened
- **WHEN** the GitHub Actions workflow triggers
- **THEN** the same lint + test + coverage pipeline SHALL run
- **AND** the PR status SHALL reflect pass/fail

### Requirement: Docker containerization

The system SHALL provide a Dockerfile based on the official OpenResty image.

#### Scenario: Docker build succeeds

- **GIVEN** the Dockerfile and source code
- **WHEN** `docker build -t linklet .` is executed
- **THEN** the image SHALL build successfully
- **AND** the image SHALL contain OpenResty, project source, and Nginx config

#### Scenario: Container starts and serves

- **GIVEN** the Docker image is built
- **WHEN** `docker run -p 8080:80 linklet` is executed
- **THEN** the server SHALL start and respond to HTTP requests

### Requirement: E2E test suite

The system SHALL have end-to-end tests covering the full resolution flow.

#### Scenario: E2E resolution test

- **GIVEN** a running OpenResty instance with PostgreSQL
- **WHEN** a short link is created and then resolved via HTTP
- **THEN** the full flow (create → cache miss → DB query → cache write → 302 redirect) SHALL work correctly

#### Scenario: E2E cache hit test

- **GIVEN** a short link has been resolved at least once (cache populated)
- **WHEN** the same short code is resolved again
- **THEN** the cache SHALL be hit
- **AND** the database SHALL NOT be queried

### Requirement: Test::Nginx runtime acceptance

Acceptance SHALL run Test::Nginx::Socket::Lua against real OpenResty and a disposable PostgreSQL database. CI SHALL propagate every failure.

#### Scenario: Real service lifecycle

- **GIVEN** the acceptance Compose stack
- **WHEN** Test::Nginx sends create, resolve, cache hit, disable and expiry requests
- **THEN** the specified HTTP responses and database effects SHALL be verified

#### Scenario: Assertion fails in CI

- **GIVEN** a failing runtime assertion
- **WHEN** the acceptance job runs
- **THEN** its exit code SHALL be nonzero without an ignore-failure fallback
