## MODIFIED Requirements
### Requirement: Regression verification
系统 SHALL 保留 Busted、Test::Nginx、PostgreSQL 集成测试及现有 CI 质量门槛，覆盖授权、迁移、解析、缓存失效、并发发号。
#### Scenario: Regression suite
- **GIVEN** 变更准备合并
- **WHEN** 运行项目现有 lint/test/acceptance 命令
- **THEN** SHALL 无新增失败，迁移前后数据核对通过
#### Scenario: Unsafe migration
- **GIVEN** 迁移核对发现 group_id、code 或 current_max 不一致
- **WHEN** 进入切流阶段
- **THEN** 发布 SHALL 被阻止
