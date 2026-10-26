# Linklet 与 lua-slds 集成契约

Linklet 复用 lua-slds 的 ShortLink、Lifecycle、Interactor 和 Resolution；保留 Tenant、Group、DomainEntry、Credential、HTTP、持久化和缓存的一致性责任。当前仍只实现 PostgreSQL，不新增 payload、业务表、通用 Service 或 DI 容器。

## 依赖与可重复构建

[固定修订](../dependencies/lua-slds.ref) 指向已公开的 lua-slds 源码提交。`make deps` 将它安装到项目的 `.test-deps/slds`；Docker 和 CI 使用相同安装脚本。`scm-1` 表示按 Git 修订安装，不代表发布了新的 LuaRocks 版本。升级依赖必须审查修订、重跑单元与真实存储验收，不使用浮动分支作为构建输入。

```sh
make deps
make test
make lint
make acceptance-docker
make docs-check
```

SLDS 自身的 metadata 解析结果扩展单独维护；Linklet 也兼容已有公开基线，通过一次 Repository 查询取得实体与域名视图，再使用纯 `Resolution.resolve()`，从实体快照构造自己的返回结果。

## 数据映射

| Linklet 数据 | SLDS 表示 | 权威位置 |
|---|---|---|
| 全局短码 code | namespace 固定为 `linklet`，code 原值 | PostgreSQL UNIQUE(code) |
| target_url | target | sl_short_link.target_url，创建后不可改 |
| group_id | metadata.group_id | sl_short_link.group_id，创建后不可改 |
| status 1 / 2 | ACTIVE / DISABLED | sl_short_link.status，停用终态 |
| expires_at | epoch 秒数或 nil | PostgreSQL timestamptz；边界转换保留小数秒 |
| 本次调用租户 | ctx.actor.tenant_id | 完成认证的 Linklet 调用方；不是短链所有者 |

Linklet 的适配器仅支持 `{group_id = uint32}` 这一 metadata 子集，拒绝未知字段，避免宣称可存任意 metadata 却静默丢失数据。group_id 仍映射原生列，无新增 JSON 存储。业务 API 不接受新的 metadata/payload 字段。ctx 不回写操作结果，也不包含数据库连接或依赖查找器。

SLDS 默认的 target 更新、停用后重启和删除不适用于 Linklet。`core/short_link_policy.lua` 声明严格策略，适配器创建仅接受 ACTIVE，更新仅接受 ACTIVE→DISABLED，删除返回 INVALID 并保持短码占用。没有声明通过 SLDS 默认策略的全部合规套件；Linklet 有自己的适用策略测试与真实 PostgreSQL 验收。

## 写入与原子性

- Core 校验 URL、Group ID、未来到期时间，执行创建前可读的授权检查。
- SLDS Interactor 接收 ctx 与 metadata，生成短码，并调用 `repository/slds.lua`。
- PostgreSQL 创建事务重新校验当前授权、Group 和 DomainEntry；Group 行锁保护首次创建与改绑的竞态。
- 停用直接执行包含当前授权和 ACTIVE 状态的原子 UPDATE；不会先读取旧记录再整行覆盖。
- 创建操作同时取得数据库事务确认的域名视图。每次调用独立捕获该视图并显式组装 Linklet 结果，不回写 ctx、不混入 metadata，也不在提交后增加读取失败窗口。已有任何短链后 Group 域名绑定冻结。
- 原有唯一约束、外键、不可变/终态触发器和单调游标保留；本次不修改历史迁移。

Hooks 仅用于观察，不承担授权拒绝、事务提交或唯一的缓存失效。业务错误在存储边界转换为稳定码；数据库异常文本不会成为 Admin 的协议。

## 解析与缓存

Repository 一次查询返回 `{link, domain, domain_status, domain_deleted}`，其中 link 为 SLDS 实体，数据库 NULL、数组和时间形式在存储边界处理。Gateway 不依赖 PostgreSQL 返回格式。

Gateway 校验请求 Host 与域名状态，使用 SLDS 判断短链状态及 `expires_at <= now`。Tenant/Group 停用仍不影响历史有效短链。metadata 不代表当前授权或 DomainEntry 状态，也不会自动输出到公开 HTTP 响应。

缓存键保留 Host+Code+generation，TTL 不超过短链剩余有效期。查询开始时捕获的 generation 显式用于写入；即使其他 Worker 在最终写入前停用，旧查询也只能写入旧代。同步过期绕过缓存，持久层故障返回 500；正在执行的旧请求允许完成。

## 部署角色和入口

`LINKLET_ROLE` 可取 `combined`（默认）、`admin`、`gateway`。Gateway 角色不组装凭证、发号器和管理处理器，也不需要 SK 加密密钥；Admin 角色不启用短链解析。Nginx 的管理和租户 API 进入 `app.handle_admin()`，短码进入 `app.handle_gateway()`；Admin Router 不包含短码路由。

管理入口仍受内部网络限制。角色开关提供实际初始化边界，入口网络、TLS 和浏览器会话仍由部署及独立认证方案负责。
