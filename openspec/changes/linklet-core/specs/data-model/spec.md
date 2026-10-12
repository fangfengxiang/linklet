## ADDED Requirements

### Requirement: Five core tables

The system SHALL maintain five domain tables: sl_link, sl_tenant, sl_scene, sl_domain_entry, sl_scene_config, plus sl_tenant_credential and sl_id_sequence (seven physical tables).

#### Scenario: Tables exist after migration

- **GIVEN** the database migration has been applied
- **WHEN** the database schema is inspected
- **THEN** all seven tables SHALL exist with their defined columns and constraints

### Requirement: Short link table structure

The system SHALL maintain sl_link with columns: id, code, target_url, scene_id, status, created_at, expires_at.

#### Scenario: Code is globally unique

- **GIVEN** a short link record exists with code "aB9xK2"
- **WHEN** another record is inserted with the same code
- **THEN** the database SHALL reject the insert (unique constraint violation)

#### Scenario: Status values are constrained

- **GIVEN** a sl_link record
- **WHEN** status is set
- **THEN** valid values SHALL be 1 (active) or 2 (disabled)

### Requirement: Relationship chain isolation

The system SHALL achieve tenant isolation through the relationship chain: link → scene → domain_entry → tenant, without redundant tenant_id in sl_link.

#### Scenario: Resolve tenant from link

- **GIVEN** a sl_link record with scene_id
- **WHEN** the system traverses scene → domain_entry → tenant
- **THEN** the tenant identity SHALL be resolved
- **AND** sl_link SHALL NOT contain tenant_id or domain_id columns

### Requirement: Domain entry immutability

The system SHALL NOT allow modification of domain entry records after creation.

#### Scenario: Domain record is immutable

- **GIVEN** a sl_domain_entry record exists
- **WHEN** an attempt is made to modify the domain field
- **THEN** the system SHALL reject the modification

### Requirement: Irreversible status transitions

The system SHALL NOT allow re-enabling a disabled link or reusing a deleted link's code.

#### Scenario: Disabled link cannot be re-enabled

- **GIVEN** a link with status=2 (disabled)
- **WHEN** an attempt is made to set status back to 1 (active)
- **THEN** the system SHALL reject the operation

#### Scenario: Deleted code cannot be reused

- **GIVEN** a link was deleted (logical delete with status=deleted or deleted_at set)
- **WHEN** a new link is created with the same code
- **THEN** the database unique constraint SHALL prevent the creation

### Requirement: Domain and scene ownership agree

A composite foreign key SHALL prevent a scene from referencing another tenant's domain entry.

#### Scenario: Foreign domain assigned to scene

- **GIVEN** a domain owned by tenant B
- **WHEN** tenant A's scene attempts to reference it
- **THEN** PostgreSQL SHALL reject the write
