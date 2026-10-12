# Linklet 设计

技术与验收设计以 [OpenSpec design](../openspec/changes/linklet-core/design.md) 为准，正式行为需求存放在 `openspec/specs/`，变更规格存放在同一变更的 `specs/`，任务状态见 `tasks.md`。

管理请求：Nginx → Router → auth → JSON → 按接口校验 → Handler → Model → PostgreSQL。
解析请求：Nginx → CacheHandler → ResolveHandler → RedirectHandler。

依赖在 `app.init` 中构造并注入；各 handler 不通过请求上下文查找服务。响应对象按请求创建。

五张领域表加凭证和号段共七张表；场景与域名租户由复合外键保持一致，链接只保留 scene_id。数据库约束保护状态终态、域名/链接不可变性和短码永久保留。

用户确认 32 位 ID 容量；精确模乘保证该范围内双射。超限拒绝，不能用数据库唯一约束代替算法正确性。

本地缓存由 Worker 共享；跨实例用 PostgreSQL 修订号轮询，默认同步新鲜度窗口 1 秒。过期缓存绕过，业务到期时间限制缓存 TTL。

详细验收证据见 [acceptance.md](acceptance.md)。
