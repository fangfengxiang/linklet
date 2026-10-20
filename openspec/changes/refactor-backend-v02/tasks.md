# Tasks — independently verifiable

## 0. Baseline and safeguards
- [x] 0.1 审计完整 `src/`、`conf/`、`migrations/`、`spec/`、`test/`、`deploy/` 与当前 OpenSpec；输出文件映射及依赖清单。
- [x] 0.2 运行 `make test`, `make lint`, `make acceptance-docker`，记录通过/失败与环境信息；不得隐藏原有失败。
- [x] 0.3 建立迁移前数据库备份/恢复演练和 schema/data 检查脚本，保留现有 ID 与短码快照。
- [x] 0.4 确认 design.md 中域名历史兼容与旧状态映射两个发布门槛；未确认时不执行破坏性切换。

## 1. Database
- [x] 1.1 创建增量迁移（不改已部署的 `001_init.sql`），添加七表目标字段、约束与索引；可在空库验证。
- [x] 1.2 迁移 `sl_scene` 内部 id 与稳定 scene_id，保留旧业务 ID 和关联；执行关联一致性测试。
- [x] 1.3 旧 Scene tenant_id 回填到 Tenant.scene_ids 并去重；校验每个旧归属均获授权。
- [x] 1.4 迁移 `sl_link` 到 `sl_short_link`，保留 code、target_url、expires_at 和 status；验证数量及 code 集合一致。
- [x] 1.5 转换 DomainEntry 状态并移除租户归属（仅在切换阶段）；验证旧 active 域名成为新 deployed。
- [x] 1.6 将发号器旧 current_max 原值转移到 sequence_key=1；并发/边界测试无重复与回绕。
- [x] 1.7 设计并测试旧版共存窗口及回退/恢复路径；破坏性 contract 独立执行。

## 2. Core and repository
- [x] 2.1 将原 models SQL 行为迁到 Repository，修正 Scene/ShortLink/DomainEntry 查询和关联；测试 CRUD 与错误处理。
- [x] 2.2 实现 Tenant.scene_ids 授权查询，创建/停用/查询均进行授权；共享 Scene 跨租户测试。
- [x] 2.3 提取 ShortLink create/gen 共享用例；验证 target_url 不可变、code 不复用、停用不可逆。
- [x] 2.4 实现域名状态转换与有 Scene 绑定不可下线，增加事务并发测试。
- [x] 2.5 保留并升级发号器 next_id、next_ids、allocate_segment；测试并发与不重叠。

## 3. Gateway and cache
- [x] 3.1 修复解析规则：不检查 Tenant/Scene status；检查 Link、expires_at、DomainEntry 和 Host。
- [x] 3.2 保留统一解析结果→Redirect 302 流程；缓存命中不必访问 DB；测试 cache hit/miss。
- [x] 3.3 缓存键改为 Host+Code，补充跨 Worker/实例失效测试；覆盖禁用、过期、改绑、域名下线。
- [x] 3.4 验证缓存 TTL 与 expires_at、数据库异常、并发更新的行为。

## 4. Admin API and security
- [x] 4.1 保留原有 create/gen/disable 路由；更新请求/响应与权限校验，补负向场景。
- [x] 4.2 HMAC 验签后校验 Credential/Tenant 状态，签名错误、过期和停用均拒绝。
- [x] 4.3 补齐 DomainEntry/Scene/SceneConfig/Tenant/Credential/ShortLink 的管理操作与 OpenAPI 契约；避免无业务需求的 CRUD。
- [x] 4.4 不向浏览器暴露 SK；文档明确 React Admin 登录认证为独立变更。

## 5. Structure, docs and CI
- [x] 5.1 分批迁移至 `lib/linklet/` 并修正 require、lua_package_path、rockspec、Nginx 和 Docker。
- [x] 5.2 保留现有 `spec/`, `test/nginx/`, `deploy/`, `openspec/`，修复路径并保证测试覆盖率门槛不回退。
- [x] 5.3 更新 README、架构图、数据模型、部署迁移手册及 OpenAPI；消除旧 tenant ownership 描述。
- [x] 5.4 执行完整单元/集成/Test::Nginx/迁移验收，输出逐项结果和遗留风险。
- [x] 5.5 确认所有新旧 specs 一致后才归档本变更；不要在验收前删除旧实现。

## 验收证据（2026-10-21）

- 基线及模块映射：[v02-audit](../../../docs/v02-audit.md)。
- 迁移/快照/恢复：`scripts/check_migrations.sh`；原 001/003 保持不变；空库和旧数据路径均覆盖。旧列暂留，contract 延后。
- 管理授权、解析、域名并发、永久短链、发号：`test/nginx/008-v02-contracts.t`；跨实例：`test/nginx/multi-instance/001-runtime.t`。
- 完整验收：Busted 150 项，单实例 Test::Nginx 96 断言，多实例 3 断言，源码覆盖率 94.50%，lint 0 警告/0 错误。
- OpenSpec 全量严格校验 10 项通过；OpenAPI 23 个操作；部署/CI YAML 和文档链接核对通过。
- 0.4 / 1.5 / 5.5 的边界：代码采用 SDD 当前域名策略和明确的旧状态映射；没有连接生产库，生产历史链接清单与业务接受范围仍是发布门槛。正式 specs 已对齐，本 change 保留不归档，旧 require 转发与兼容列继续保留供升级审计。详见 [迁移手册](../../../docs/v02-migration.md)。
