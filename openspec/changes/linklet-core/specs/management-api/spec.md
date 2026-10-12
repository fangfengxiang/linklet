## ADDED Requirements

### Requirement: Create short link

The system SHALL provide a POST endpoint to create a short link.

#### Scenario: Create with valid parameters

- **GIVEN** an authenticated request with target_url and scene_id
- **WHEN** POST /api/v1/shorten/create is called
- **THEN** the system SHALL generate a short code
- **AND** the system SHALL persist the link record to PostgreSQL
- **AND** the response SHALL include the generated code
- **AND** the response SHALL have status code 200 with JSON body {code:0, message:"success", data:{code:"xxx"}}

#### Scenario: Missing target_url

- **GIVEN** a request without target_url
- **WHEN** POST /api/v1/shorten/create is called
- **THEN** the response SHALL have status code 400 with error message

#### Scenario: Invalid scene_id

- **GIVEN** a request with a scene_id that does not belong to the authenticated tenant
- **WHEN** POST /api/v1/shorten/create is called
- **THEN** the response SHALL have status code 403 with error message

### Requirement: Generate short link with URL

The system SHALL provide a POST endpoint to create a short link and return the full short URL.

#### Scenario: Generate with valid parameters

- **GIVEN** an authenticated request with target_url and scene_id
- **WHEN** POST /api/v1/shorten/gen is called
- **THEN** the system SHALL create the link (same as /api/v1/shorten/create)
- **AND** the system SHALL resolve the scene's domain entry
- **AND** the response SHALL include both code and short_url (domain + "/" + code)

#### Scenario: Domain entry not found

- **GIVEN** a scene_id whose domain entry is deleted or not configured
- **WHEN** POST /api/v1/shorten/gen is called
- **THEN** the system SHALL return an error indicating domain is not available
- **AND** the system SHALL NOT retry link creation

### Requirement: Disable short link

The system SHALL provide an endpoint to disable (deactivate) a short link.

#### Scenario: Disable active link

- **GIVEN** an authenticated request for an active link
- **WHEN** PUT /api/v1/shorten/disable is called with the code
- **THEN** the system SHALL set the link status to 2 (disabled)
- **AND** the system SHALL invalidate the cache entry
- **AND** the response SHALL confirm success

#### Scenario: Disable already disabled link

- **GIVEN** a link that is already disabled
- **WHEN** PUT /api/v1/shorten/disable is called
- **THEN** the response SHALL return an error indicating the link is already disabled
- **AND** the system SHALL NOT change any state

### Requirement: Unified response format

The system SHALL return all management API responses in a unified JSON format.

#### Scenario: Success response

- **GIVEN** any successful management API call
- **WHEN** the response is generated
- **THEN** the JSON body SHALL have fields: code (0 for success), message ("success"), data (result object)

#### Scenario: Error response

- **GIVEN** any failed management API call
- **WHEN** the response is generated
- **THEN** the JSON body SHALL have fields: code (non-zero error code), message (error description), data (null)

### Requirement: Tenant-constrained disable and endpoint validation

Disable SHALL accept only the required code parameter and SHALL update only links owned by the authenticated tenant.

#### Scenario: Foreign tenant code

- **GIVEN** tenant A owns an active link and tenant B is authenticated
- **WHEN** tenant B attempts to disable that code
- **THEN** the response SHALL be 404 and the link SHALL remain active

#### Scenario: Missing disable code

- **GIVEN** an authenticated disable request without code
- **WHEN** endpoint validation runs
- **THEN** the response SHALL be 400 JSON with data:null, not 500
