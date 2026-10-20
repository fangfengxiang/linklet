## MODIFIED Requirements
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
