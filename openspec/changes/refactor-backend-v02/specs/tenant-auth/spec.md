## MODIFIED Requirements
### Requirement: Group authorization is a tenant array
Tenant SHALL 通过 `group_ids` 数组获得 Group 管理权限；Group SHALL NOT 使用 `tenant_id` 表示所有权；授权需校验 Tenant 有效状态。
#### Scenario: Shared group management
- **GIVEN** Tenant A、B 都授权 Group S
- **WHEN** B 停用 A 在 S 创建的短链
- **THEN** 操作 SHALL 成功（满足其他条件时）
#### Scenario: Unauthorized tenant
- **GIVEN** Tenant C 未授权 Group S
- **WHEN** C 管理 S 的短链
- **THEN** 系统 SHALL 拒绝且不修改数据
### Requirement: Credential validity
系统 SHALL 在验签成功后确认 Credential 与 Tenant 均启用；Credential 停用 SHALL 不可恢复，AK SHALL 不复用。
#### Scenario: Disabled credential
- **GIVEN** 凭证已停用
- **WHEN** 提交签名正确的请求
- **THEN** 请求 SHALL 被拒绝
