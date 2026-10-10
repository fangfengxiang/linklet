## ADDED Requirements

### Requirement: Segment-based ID allocation

The system SHALL allocate IDs in segments (batches) from PostgreSQL to reduce per-request database access.

#### Scenario: Allocate a new segment

- **GIVEN** the local segment is exhausted or not yet allocated
- **WHEN** the system needs a new ID
- **THEN** the system SHALL atomically reserve a segment of sequential IDs from PostgreSQL
- **AND** the segment size SHALL be configurable (default 1000)

#### Scenario: Consume ID from local segment

- **GIVEN** the local segment has remaining IDs
- **WHEN** the system needs a new ID
- **THEN** the system SHALL return the next ID from the local segment
- **AND** the system SHALL NOT access the database

#### Scenario: Segment exhaustion

- **GIVEN** the local segment is fully consumed
- **WHEN** the system needs a new ID
- **THEN** the system SHALL allocate a new segment from PostgreSQL

### Requirement: Concurrent segment allocation safety

The system SHALL ensure multiple OpenResty workers and multiple Pods do not receive overlapping ID segments.

#### Scenario: Two workers allocate simultaneously

- **GIVEN** two OpenResty workers both need a new segment at the same time
- **WHEN** both request a segment from PostgreSQL
- **THEN** the segments SHALL be disjoint (non-overlapping)
- **BECAUSE** PostgreSQL atomic UPDATE ensures exclusive segment reservation

#### Scenario: Worker restart does not duplicate IDs

- **GIVEN** a worker crashes after consuming part of its segment
- **WHEN** the worker restarts and allocates a new segment
- **THEN** the new segment SHALL start after the previously reserved maximum
- **AND** unconsumed IDs from the old segment SHALL be lost (gaps allowed)

### Requirement: Gap tolerance

The system SHALL allow gaps in ID allocation, requiring only uniqueness.

#### Scenario: Gap in ID sequence

- **GIVEN** a worker restart caused some IDs to be skipped
- **WHEN** a new ID is allocated
- **THEN** the ID SHALL be unique (never previously allocated)
- **AND** the system SHALL NOT attempt to fill gaps
