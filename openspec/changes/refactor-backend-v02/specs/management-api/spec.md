## MODIFIED Requirements
### Requirement: Single short-link creation path
`create` 与 `gen` SHALL 复用同一个创建用例；`gen` 只增加完整短 URL 输出。创建 SHALL 校验租户 Scene 授权、Scene 启用及 DomainEntry 已投产。
#### Scenario: Create and gen parity
- **GIVEN** 同一有效输入和授权
- **WHEN** 分别调用 create 与 gen
- **THEN** 两者 SHALL 使用相同创建规则；gen SHALL 返回 short_url
#### Scenario: Immutable target
- **GIVEN** 短链已创建
- **WHEN** 尝试修改 target_url
- **THEN** 系统 SHALL 拒绝修改
### Requirement: Terminal disable
短链停用 SHALL 为终态，且停用操作 SHALL 重新验证调用租户对所属 Scene 的授权。
#### Scenario: Unauthorized disable
- **GIVEN** 调用租户无 Scene 授权
- **WHEN** 请求停用某短码
- **THEN** 操作 SHALL 被拒绝，短链仍有效
