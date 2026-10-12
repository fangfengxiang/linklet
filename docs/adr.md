# Linklet 架构决策记录（ADR）索引

> 本文件是所有架构决策的总览索引，按领域模块组织。

## 设计哲学

三原则：
1. **OpenResty 原生**：不引入额外 Web 框架，利用 Nginx + Lua 原生能力。
2. **显式依赖注入**：依赖通过构造参数注入，拒绝 Context 作为服务定位器。
3. **读路径优先**：解析链路缓存优先，写入可靠，未来可扩展。

## 决策总览

| 编号 | 决策 | 模块 | 状态 |
|------|------|------|------|
| ADR-001 | 采用 OpenResty + Lua 原生架构，不引入 Web 框架 | 架构 | 已决 |
| ADR-002 | 短链只记录 scene_id，不冗余 tenant_id/domain_id | 数据模型 | 已决 |
| ADR-003 | 短码全局唯一，数据库唯一索引保证 | 数据模型 | 已决 |
| ADR-004 | 短码生成：黄金比例混淆 + Base62 编码 | 短码算法 | 已决 |
| ADR-005 | 发号器采用号段批量分配模式 | 发号器 | 已决 |
| ADR-006 | 状态不可逆：停用/删除是终态 | 领域规则 | 已决 |
| ADR-007 | 解析链路：CacheHandler → ResolveHandler → RedirectHandler | 架构 | 已决 |
| ADR-008 | 缓存使用 ngx.shared.DICT | 基础设施 | 已决 |
| ADR-009 | AK/SK + HMAC 签名认证 | 安全 | 已决 |
| ADR-010 | pgmoon 作为 PostgreSQL 驱动 | 基础设施 | 已决 |
| ADR-011 | 短码生成算法碰撞修正：16 位分段精确实现 32 位双射，超限拒绝（用户确认） | 短码算法 | 已决 |
| ADR-012 | Docker + Kubernetes 部署 | 部署 | 已决 |

ADR-013：跨实例使用 PostgreSQL 修订号同步；默认 0.5 秒轮询，1 秒新鲜度窗口。

ADR-014：Test::Nginx + 真实 PostgreSQL 为运行时验收基准，mock 测试仅作为补充。
