# Design — Linklet Backend v0.2

## 1. Decisions
1. **两个仓库、四个逻辑模块**：本仓库承载 Core、Admin API、Gateway；React Admin Web 在独立 `linklet-admin` 仓库。
2. **Lua-native**：模块根为 `lib/linklet/`，通过 `require "linklet.*"` 加载；OpenResty 是唯一 v1 Host。直接构造/注入依赖，Context 仅为请求信息。
3. **Repository 即 SQL 访问层**：旧 `src/models/*` 迁到 `repository/*`，不再保留平行的 ORM/DAO/Model 层；Core 放不依赖 `ngx` 的规则和必要用例，不为简单 CRUD 强制增加 Service。
4. **Admin 和 Gateway 只共享领域规则/Repository**，Gateway 缓存命中不经过 Admin 或完整创建用例。
5. **保留现有工程资产**：`spec/`、`test/nginx/`、`deploy/`、`openspec/`、`conf/`。

## 2. Target tree
```text
lib/linklet/
  app.lua
  core/{short_link,group,domain_entry,tenant,credential}.lua
  admin/{routes,auth}.lua
  admin/handlers/{short_link,group,group_config,domain_entry,tenant,credential}.lua
  gateway/{handler,resolver,redirect}.lua
  repository/{short_link,group,group_config,domain_entry,tenant,credential}.lua
  db/postgres.lua
  cache/{local,sync}.lua
  id/{generator,obfuscator}.lua
  http/{request,response}.lua
conf/  migrations/  spec/  test/nginx/  test/benchmark/  deploy/
api/openapi.yaml
```
这是目标模块映射，不要求未存在的文件全部创建；先审计真实代码，再迁移已有模块。

## 3. Data model (seven tables)
| Table | Contract |
|---|---|
| `sl_domain_entry` | 全局唯一 `domain`，无 tenant_id；`tag`/description；状态 1新增→2投产→3下线，禁止回退；有 Group 绑定不可下线 |
| `sl_group` | 内部 `id` 主键、稳定唯一 `group_id` (1..4294967295)；`domain_entry_id` 非空；status 1启用/2停用；不属于 Tenant |
| `sl_group_config` | `(group_id, config_key)` 唯一；配置继承应用默认值；不创建 link_type |
| `sl_tenant` | `group_ids BIGINT[] NOT NULL DEFAULT '{}'`；status 1/2；无关联表；授权集合去重、校验存在性 |
| `sl_tenant_credential` | access_key 唯一；加密 SK；status 1/2，停用终态，AK 不复用 |
| `sl_short_link` | code 全局唯一且永久不复用；target_url 不可修改；group_id 关联业务标识；status 1/2，停用终态；expires_at NULL 不到期 |
| `sl_id_sequence` | `sequence_key INTEGER PRIMARY KEY`，1=SHORT_LINK；current_max 单调，step 默认 1000，32-bit 上限 |

`group_id` 为稳定业务标识，006 从旧 `scene_id` 原值重命名。若保留 `sl_group.id` 与 `group_id` 双标识，FK 必须明确引用 `group_id`，迁移需保留旧值。对 `group_ids` 数组无法建立常规 FK，应用层需校验。

## 4. Authorization and behavior
- HMAC 验证 access_key/签名/时间戳后，还要验证 Credential 与 Tenant 均启用；请求重放防护沿用现有策略并审计安全边界。
- 管理短链：Tenant 存在、启用且其 `group_ids` 包含短链的 Group；被授权的不同租户可共同管理同 Group 的短链。
- 创建：Group 启用、绑定的 DomainEntry 已投产、租户有 Group 权限；验证 target_url 安全策略与 expires_at；统一创建函数返回 code/可生成 short_url。
- 解析：ShortLink 启用、未过期、域名处于投产状态且请求 Host 匹配 Group 当前绑定的域名；**不以 Tenant/Group 状态阻止既有短链**。返回结构化解析结果，最后 Redirect 输出 302。
- 关闭 DomainEntry：检查所有未删除且仍绑定的 Group；检查和下线状态转换需在同一事务中串行化与 Group 绑定变更（行锁或等效方案）；禁止仅依赖 UI 判断。
- Group 只在没有任何短链时允许改绑域名。一旦创建短链（包括之后停用或到期），domain_entry_id 冻结；不允许软删除 Group 绕过保护。短链插入与改绑持有同一 Group 行锁；创建返回插入事务确认的域名。ShortLink 是独立聚合，Group 仅定义归属与策略边界。

## 5. Cache consistency
缓存键必须区分 Host 与 Code（如规范化 Host+Code），不能仅用 Code 缓存跨域名解析。缓存结果包含解析所需状态/过期时间，TTL 不超过短链有效期；停用短链、Group 改绑域名、域名下线时跨 Worker/实例失效或通过版本号/广播保证有界一致性。沿用并验证现有 `cache_sync`；不得声称只清当前 Worker 就完成失效。数据库不可用时按明确的可用性策略处理，禁止返回已知失效链接。

## 6. ID allocation
复用现有 PostgreSQL 原子 UPDATE RETURNING、worker 本地号段和信号量。迁移旧 `id=1,current_max` 至 `sequence_key=1,current_max`；`next_id()`、`next_ids(count)`、`allocate_segment(size?)` 号段互斥不重叠，`current_max` 不回退、不回绕。支持耗尽错误。

## 7. Deployment and migration
1. 备份、检查旧 Schema 和数据质量（tenant/group 归属、重复授权、域名状态、已发短码）。
2. expand：新增兼容字段、表/索引；避免在旧应用运行期间直接重命名或删除其依赖的列。
3. backfill：旧 `sl_group.tenant_id` → 对应 `sl_tenant.group_ids`，去重；保留 `group_id` 和短链关联；`sl_link` → `sl_short_link` 通过兼容视图或停机窗口切换；转换域名状态时显式映射，禁止将旧 active=1 误映射成新=1（新增）。
4. verify：授权数量、链接数量、code 集合、关联完整性、`current_max`、域名映射、缓存键、旧短链跳转。
5. switch：发布新应用与 Nginx 配置，逐步切流并监控。
6. contract：确认无旧版本读写后才删除旧列/视图/索引；清理旧模块。

## 8. Open questions / release gates
- **旧 DomainEntry 状态映射**：旧 1=active/2=disabled/3=deleted，新 1=new/2=deployed/3=offline；需数据迁移映射表与历史状态处理方案。
- **域名稳定性已决**：已有短链后禁止改绑；006 无法恢复上线前已被改绑的历史 URL，仍需核对历史清单。
- **浏览器登录**：独立前端不能持久化 AK/SK 到浏览器；会话认证是独立后续变更，本次仅确保 Admin API 认证契约不被误用。
- **已有 `openspec/specs` 冲突**：按变更规范更新/合并，不能同时维护相反的 SHALL 规则。
