## MODIFIED Requirements
### Requirement: Seven-table canonical schema
系统 SHALL 使用七表目标模型：`sl_domain_entry`, `sl_group`, `sl_group_config`, `sl_tenant`, `sl_tenant_credential`, `sl_short_link`, `sl_id_sequence`；`group_id` 是稳定业务标识，由旧 `scene_id` 原值迁移；ShortLink 为独立聚合。
#### Scenario: Group referenced by links
- **GIVEN** 已存在 group_id=100 与其短链
- **WHEN** 迁移内部主键
- **THEN** 原 group_id 与短链关联 SHALL 保持不变
#### Scenario: Global short code uniqueness
- **GIVEN** 某短码已被停用或过期
- **WHEN** 新建短链
- **THEN** 系统 SHALL 拒绝再次使用该短码
### Requirement: Domain status lifecycle
DomainEntry SHALL 按 1新增→2投产→3下线不可逆转换；有 Group 当前绑定时 SHALL 禁止下线。
#### Scenario: Bound domain cannot be disabled
- **GIVEN** 某 DomainEntry 被 Group 绑定
- **WHEN** 请求下线
- **THEN** 请求 SHALL 失败，且 DomainEntry 状态不变

### Requirement: Stable issued short URLs
Group SHALL 在存在任何 ShortLink 后冻结 domain_entry_id，包含已停用和已过期短链；ShortLink 的 code、target_url、group_id SHALL 创建后不可变，code 全局唯一且永久不复用。
#### Scenario: Issued URL cannot be moved
- **GIVEN** Group 已有短链
- **WHEN** 通过 API 或 SQL 改绑域名或软删除该 Group
- **THEN** 系统 SHALL 拒绝，旧 URL 的域名保持不变
#### Scenario: Concurrent first link and rebind
- **GIVEN** 空 Group 的首次创建与域名改绑并发
- **WHEN** 两个操作提交
- **THEN** 它们 SHALL 通过 Group 行锁串行化；先创建则拒绝改绑，先改绑则创建返回新域名 URL
