## ADDED Requirements

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
- **AND** subsequent resolution SHALL return HTTP 404/410

### Requirement: Redirect response

The system SHALL return HTTP 302 redirect for valid short codes.

#### Scenario: Successful redirect

- **GIVEN** a valid active link with target_url "https://example.com/page"
- **WHEN** the short code is resolved
- **THEN** the response SHALL have status code 302
- **AND** the response SHALL have a Location header with the target URL
