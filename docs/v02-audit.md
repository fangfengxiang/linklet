# v0.2 实现审计与边界

2026-10-21，审计本地源仓库的全部 Lua 模块、迁移、测试、部署与 CI。依据 `docs/data-model.md`、`docs/improve.md` 及 `refactor-backend-v02` SDD；字段命名冲突按 SDD 保留 `target_url`，不引入 `dest_url` 别名。

## 基线

- `make test`：143 项通过；`make lint`：0 警告、0 错误。
- `make acceptance-docker`：单实例 75 个断言、多实例 3 个断言通过，合并覆盖率 90.68%。
- Docker 需要本机 daemon 权限。首次直接运行被沙箱拒绝，授权连接后完整基线通过。
- 未连接线上数据库，未执行线上切换；未修改 001/003 的已部署 SQL。

## 文件映射与依赖

| 旧入口 | 新实现 |
|---|---|
| src/app.lua / src/linklet.lua | lib/linklet/app.lua；require("linklet") 包入口保留 |
| src/models/base_model.lua | lib/linklet/repository/base.lua |
| src/models/{link,scene,domain_entry,tenant,tenant_credential}.lua | lib/linklet/repository/{short_link,scene,domain_entry,tenant,credential}.lua |
| src/lib/{database,cache,cache_sync}.lua | lib/linklet/{db/postgres,cache/local,cache/sync}.lua |
| src/lib/{id_generator,obfuscator}.lua | lib/linklet/id/{generator,obfuscator}.lua |
| src/lib/{request,response}.lua / src/router.lua | lib/linklet/http/{request,response,router}.lua |
| src/middleware/{json,validate,auth}.lua | lib/linklet/{http/json,http/validate,admin/auth}.lua |
| src/shorten/handler.lua | lib/linklet/admin/handlers/short_link.lua + core/short_link.lua |
| src/shorten/{cache_handler,resolve_handler,redirect_handler}.lua | lib/linklet/gateway/{cache,resolver,redirect}.lua |
| src/admin/{tenant_handler,credential_handler}.lua | lib/linklet/admin/handlers/{tenant,credential}.lua |
| src/lib/crypto.lua / src/routes.lua | lib/linklet/crypto.lua / lib/linklet/admin/routes.lua |

旧 src 文件只转发加载，避免存在两套实现。新增 SceneConfig Repository 和资源管理 HTTP 适配器；简单 CRUD 不增加 Service。没有新增框架、DI 容器、数据库表或前端。

运行依赖：OpenResty/LuaJIT、pgmoon 1.18+、lua-cjson 2.1+；HMAC、AES-GCM、随机数使用现有 OpenResty/OpenSSL 能力。验证依赖：Busted、LuaCov、luacheck、Test::Nginx 0.32、Perl/prove、PostgreSQL 16 客户端、Docker Compose。保留现有 CI 的 Lua 5.1/5.3/LuaJIT 矩阵。

## 决策

- 保存所有历史短码，不回收 ID；批量分配部分失败可留下空洞，不能回填。
- Scene/Tenant 可停用和恢复；短链、凭证停用是终态；域名只能新增→投产→下线。
- 解析不检查 Tenant/Scene 状态；域名使用当前绑定策略。SceneConfig 目前为 KV 管理，未臆造参数透传业务规则。
- 缓存使用 Host+Code+generation。默认最大传播新鲜度窗口为同步周期两倍，超时绕过缓存；所有更新触发持久 revision。局部停用立即切换 generation，已在途的旧请求允许完成。
- 凭证查询同时检查 Tenant 启用和未删除；签名保留 300 秒窗口，窗口内不保证恰好一次。不把 AK/SK 当浏览器会话认证。

行锁与跨行规则参考 [PostgreSQL 16 锁文档](https://www.postgresql.org/docs/16/explicit-locking.html) 和 [约束文档](https://www.postgresql.org/docs/16/ddl-constraints.html)。最终行为由真实 PostgreSQL 的并发测试验证。

## 后续发布门槛

生产历史域名兼容清单和状态分布必须由部署方核对。本次采用明确映射并提供阻断检查；不把测试库验收当作生产授权。迁移步骤见 [迁移手册](v02-migration.md)，最终测试证据见 [验收记录](acceptance.md)。
