## MODIFIED Requirements
### Requirement: Lua module boundaries
系统 SHALL 以 `lib/linklet/` 为 Lua 模块根目录；Admin 与 Gateway SHALL 不互相依赖；Core SHALL 不直接访问 ngx/HTTP 请求或 SQL；Repository SHALL 封装 SQL；Core SHALL 返回领域错误，由 Admin 映射为 HTTP 状态及响应码。
#### Scenario: Core standalone tests
- **GIVEN** 无 OpenResty 运行环境
- **WHEN** 执行纯 Core 单元测试
- **THEN** 测试 SHALL 能使用注入的 Repository 替身运行
### Requirement: Safe incremental migration
已部署数据库 SHALL 使用增量迁移，保留原 code、group_id、current_max、AK；旧 active 域名状态 SHALL 正确映射到新 deployed。
#### Scenario: No sequence reset
- **GIVEN** 生产数据库已有短码
- **WHEN** 运行迁移
- **THEN** 发号状态 SHALL 不重置，短码集合 SHALL 不丢失
