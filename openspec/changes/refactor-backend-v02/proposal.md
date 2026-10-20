# Change: Refactor Linklet Backend v0.2

## Why
现有 `src/` 实现使用 Scene 属于单一 Tenant 的旧模型，与确定的七表领域模型冲突。现有 `src/shorten/handler.lua` 重复实现 create/gen；`src/models/link.lua` 和 `src/shorten/resolve_handler.lua` 在解析时错误依赖 Tenant/Scene 状态。需要先保证行为正确，再迁移到 Lua-native `lib/linklet/`。

## What Changes
- 七表结构与约束：`sl_domain_entry`、`sl_scene`、`sl_scene_config`、`sl_tenant`、`sl_tenant_credential`、`sl_short_link`、`sl_id_sequence`。
- Tenant→Scene 从所有权变为 `tenant.scene_ids` 授权；共享 Scene 的租户可管理同一 Scene 的短链。
- Admin 创建、生成、停用复用 Core 规则；Gateway 以 Host+Code 解析，统一缓存/DB 结果后输出 302。
- 将 Lua 模块逐步迁至 `lib/linklet/{core,admin,gateway,repository,db,cache,id,http}`，保留现有测试与部署资产。
- 保留 AK/SK HMAC、AES-256-GCM、PostgreSQL 号段、32-bit 混淆和 Base62；不引入新的框架、DI 容器或额外业务表。

## Scope
**In:** OpenResty/Lua 后端、SQL 迁移、现有 API、缓存、测试、文档、OpenAPI 契约。
**Out:** React 管理界面、浏览器登录实现、独立服务拆分、短链类型表、分组模型。命名继续采用 `scene_id`，不改 `group_id`。

## Compatibility and migration
已有部署使用增量迁移；保留旧 `scene_id`、Code、target_url、AK 与 `current_max`。禁止重新发号、重用短码或直接破坏已部署的 `001_init.sql`。原有 `/api/v1/shorten/{create,gen,disable}` 路径原则上保留，兼容性变更需显式说明。

## Rollback
上线前备份并验证恢复；数据库迁移采用 expand→backfill→verify→switch→contract，破坏性删列放在独立后续版本。切流前可回退应用；切流后如发生不可逆 schema/授权迁移，优先前向修复或使用经过演练的备份恢复，不承诺任意时点直接 DOWN 回滚。

## Dependencies
以 `openspec/specs/` 现有能力规范为基线，本变更中的 delta specs 只描述新增/修改的行为。`openspec/changes/linklet-core/` 为已有变更，不覆盖。
