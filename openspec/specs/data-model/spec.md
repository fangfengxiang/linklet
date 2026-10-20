# data-model Specification

## Purpose

Maintain shared-scene authorization, immutable codes and seven canonical tables.

## Requirements

### Requirement: Seven-table canonical schema
系统 SHALL 使用七表目标模型：`sl_domain_entry`, `sl_scene`, `sl_scene_config`, `sl_tenant`, `sl_tenant_credential`, `sl_short_link`, `sl_id_sequence`；`scene_id` 是稳定业务标识，不能替换为 `group_id`。
#### Scenario: Scene referenced by links
- **GIVEN** 已存在 scene_id=100 与其短链
- **WHEN** 迁移内部主键
- **THEN** 原 scene_id 与短链关联 SHALL 保持不变
#### Scenario: Global short code uniqueness
- **GIVEN** 某短码已被停用或过期
- **WHEN** 新建短链
- **THEN** 系统 SHALL 拒绝再次使用该短码
### Requirement: Domain status lifecycle
DomainEntry SHALL 按 1新增→2投产→3下线不可逆转换；有 Scene 当前绑定时 SHALL 禁止下线。
#### Scenario: Bound domain cannot be disabled
- **GIVEN** 某 DomainEntry 被 Scene 绑定
- **WHEN** 请求下线
- **THEN** 请求 SHALL 失败，且 DomainEntry 状态不变
