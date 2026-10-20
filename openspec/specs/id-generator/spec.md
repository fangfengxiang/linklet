# id-generator Specification

## Purpose

Allocate disjoint bounded 32-bit ID segments safely across workers and instances.

## Requirements

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

### Requirement: Inclusive disjoint bounds and coroutine safety

The system SHALL reserve [old_max+1,new_max] and serialize worker-local segment allocation while database I/O yields.

#### Scenario: Adjacent segments

- **GIVEN** segment size 2 and current_max 0
- **WHEN** two segments are reserved and consumed
- **THEN** the IDs SHALL be 1,2,3,4 without overlapping endpoints

#### Scenario: Concurrent worker coroutines

- **GIVEN** 20 coroutines share an exhausted local generator
- **WHEN** all request an ID
- **THEN** each SHALL receive a distinct ID

#### Scenario: ID space exhausted

- **GIVEN** current_max is 4294967295
- **WHEN** a segment is requested
- **THEN** the request SHALL fail explicitly without resetting or wrapping the sequence

### Requirement: Durable non-overlapping segments
系统 SHALL 使用 `sequence_key` 区分发号用途；SHORT_LINK=1；current_max SHALL 单调不减且不超过 4294967295。`next_id`、`next_ids`、`allocate_segment` SHALL 不分配重叠 ID。
#### Scenario: Migrated sequence
- **GIVEN** 旧 current_max=N
- **WHEN** 执行数据迁移并再次发号
- **THEN** 所有新 ID SHALL 大于 N
#### Scenario: Concurrent allocations
- **GIVEN** 多 Worker 同时申请号段
- **WHEN** 分配完成
- **THEN** 任意两个号段 SHALL 不重叠
#### Scenario: Exhausted space
- **GIVEN** 剩余 ID 不足
- **WHEN** 请求超出上限的号段
- **THEN** 系统 SHALL 返回错误且不得回绕
