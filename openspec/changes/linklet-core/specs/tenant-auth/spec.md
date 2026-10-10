## ADDED Requirements

### Requirement: AK/SK authentication

The system SHALL authenticate management API requests using AK (Access Key) and SK (Secret Key) with HMAC signature.

#### Scenario: Valid AK/SK signature

- **GIVEN** a request with valid AK and correct HMAC signature using the corresponding SK
- **WHEN** the request reaches the auth middleware
- **THEN** the system SHALL verify the signature
- **AND** the system SHALL extract tenant_id from the credential
- **AND** the request SHALL proceed to the handler

#### Scenario: Invalid signature

- **GIVEN** a request with valid AK but incorrect HMAC signature
- **WHEN** the request reaches the auth middleware
- **THEN** the system SHALL reject the request with HTTP 401
- **AND** the response SHALL indicate authentication failure

#### Scenario: Unknown AK

- **GIVEN** a request with an AK that does not exist in the database
- **WHEN** the request reaches the auth middleware
- **THEN** the system SHALL reject the request with HTTP 401

#### Scenario: Disabled credential

- **GIVEN** a request with a valid AK whose credential status is disabled
- **WHEN** the request reaches the auth middleware
- **THEN** the system SHALL reject the request with HTTP 401

### Requirement: SK encrypted storage

The system SHALL store Secret Keys in encrypted form in the database.

#### Scenario: SK is encrypted at rest

- **GIVEN** a credential record in the database
- **WHEN** the SK field is inspected
- **THEN** the stored value SHALL be encrypted ciphertext
- **AND** the plaintext SK SHALL NOT be stored

#### Scenario: SK decryption for verification

- **GIVEN** a credential with encrypted SK
- **WHEN** the auth middleware needs to verify a signature
- **THEN** the system SHALL decrypt the SK using the configured encryption key
- **AND** the decrypted SK SHALL be used for HMAC verification only (not logged or cached)

### Requirement: Single authentication pass

The system SHALL authenticate only once per request, passing the verified tenant identity through the request context.

#### Scenario: Authenticated identity propagates

- **GIVEN** a request that has passed authentication
- **WHEN** the request reaches the controller
- **THEN** the controller SHALL read tenant_id from the request context
- **AND** the controller SHALL NOT re-authenticate or re-read AK from request parameters
