# Linklet 验收记录

验收方式：Test::Nginx::Socket::Lua 启动真实 OpenResty，以 TCP/HTTP 访问生产 `conf/locations.conf`，使用 pgmoon 连接隔离 PostgreSQL。busted 作为补充单元测试。测试不能接受“302 或 404 都算成功”，也不能忽略失败退出码。

## 需求、修复与验收对应

| 项目 | 对齐后的要求与修复 | 验收证据 |
|---|---|---|
| 号段边界 | 分配闭区间 `[old_max+1,new_max]`；无重复端点 | `001-id-generator.t` TEST 1 |
| Worker 协程 | 仅分配慢路径使用 semaphore；20 协程不重复 | `001-id-generator.t` TEST 2 |
| 短码容量 | 用户确认 32 位；16 位分段精确模乘；超限拒绝 | `001-id-generator.t` TEST 3–4 |
| 停用参数 | disable 只要求 code；重复停用返回 404 | `002-management.t` TEST 1 |
| 多租户停用 | UPDATE 通过场景限定 tenant_id，外租户不能修改 | `002-management.t` TEST 2 |
| 参数及响应 | 参数错误 400、场景越权 403、JSON data:null | `002-management.t` TEST 3 |
| 参数类型与数据库错误 | false/数组字段返回 400；数据库失败不伪装成 404 | `002-management.t` TEST 5 |
| 完整短链 | 补 HTTP(S) scheme；停用域名不生成链接 | `002-management.t` TEST 4 |
| 解析缓存 | 冷缓存写入；热缓存不查模型；停用后 410 | `003-resolution.t` TEST 1 |
| PostgreSQL 过期 | 数据库返回 epoch；时区不影响过期判断 | `003-resolution.t` TEST 2 |
| 缓存过期 | TTL 不超过剩余有效期 | `003-resolution.t` TEST 3 |
| 并发失效 | generation 防止停用后被旧查询重新写入缓存 | `003-resolution.t` TEST 4 |
| 跨实例缓存 | 独立缓存修订同步；同步过期则绕过缓存 | `003-resolution.t` TEST 5 |
| 签名完整性 | query 和原始 body 纳入签名；篡改返回 401 | `004-auth-crypto.t` TEST 1 |
| 认证边界 | 时间戳必需；过期、错误签名、停用凭证均 401 | `004-auth-crypto.t` TEST 2 |
| SK 存储 | AES-256-GCM 随机 nonce；篡改/旧 XOR 拒绝 | `004-auth-crypto.t` TEST 3 |
| 请求体 | 非 JSON 对象拒绝；落盘 body 完整校验签名 | `004-auth-crypto.t` TEST 4 |
| 数据库连接 | 修正 pgmoon.new；连接复用；标量转义 | `005-database-models.t` TEST 1 |
| 数据库事务 | nil/error、异常均回滚；正常回调提交 | `005-database-models.t` TEST 2 |
| 数据不变量 | 所属租户、状态、域名不可变、短码永久保留 | `005-database-models.t` TEST 3 |
| 健康检查 | readiness 查询数据库；liveness 独立 | `006-runtime-admin.t` TEST 1 |
| 管理后台 | 租户/安全凭证创建、列表、停用闭环 | `006-runtime-admin.t` TEST 2 |
| 包与模型 | linklet 包入口；继承更新仍受数据库约束 | `006-runtime-admin.t` TEST 3 |
| 生产初始化 | 提取实际 init 配置；保留环境变量；定时器工作 | `007-production-init.t` TEST 1 |

## 执行

推荐隔离容器验收：

```sh
make acceptance-docker
# 查看结果后清理仅属于验收的容器和卷：
docker compose -p linklet-acceptance -f deploy/acceptance-compose.yml down --volumes
```

该命令先在另一个一次性数据库验证迁移正向/逆向，再运行 lint、busted、Test::Nginx 和合并源码覆盖率（阈值 80%）。任何一步失败都会返回非零退出码。数据库为 `linklet_test`，固定公开凭证只用于隔离测试。

本机已安装 OpenResty、Test::Nginx、pgmoon、LPeg 时：

```sh
make test
make lint
make acceptance
# 单独复验一个问题：
bash scripts/test_nginx.sh test/nginx/003-resolution.t
make coverage
```

本机默认 PostgreSQL 为 `127.0.0.1:15432`；`LINKLET_TEST_PGPORT` 可以改变端口。测试会清空 `linklet_test` 内的业务表，必须使用独立数据库。

## 验收结果

2026-10-13 最终隔离 Compose 流程返回 0：

- 单实例 Test::Nginx：7 个文件、75 个断言通过。
- 两个真实生产镜像实例：1 个 Test::Nginx 文件、3 个断言通过（独立号段、两侧解析、跨实例停用传播）。
- busted：143 项通过；luacheck：0 警告、0 错误。
- 合并源码覆盖率：90.68%，门槛 80%。
- 001/003 正向迁移、003_down/001_down 逆序回滚：通过。
- LuaRocks 实际安装及安装后的 require("linklet")：通过。
- 生产镜像 Nginx 配置校验：通过；缺少加密密钥时实际启动返回失败：符合预期。
- 文档文件、相对链接、OpenSpec 严格校验、部署/CI YAML 解析：通过。

可复验命令：`make acceptance-docker`。正式规格同步到 `openspec/specs/`；任务清单 65/65 已完成。

## 一致性与边界

- 正整数 ID 最大 4294967295。号段跨越上限会被拒绝；剩余不足一个号段时可调整段大小，不会回绕。
- 黄金比例混淆可逆，不提供密码学不可预测性；公开短码不是权限凭证。
- 同实例停用即时删除缓存。默认跨实例同步窗口为 1 秒，属于有界传播；正在执行的旧请求可完成。定时器或数据库不可用时，同步过期会绕过缓存。
- `003-resolution.t` 验证独立 shared dict；`007-production-init.t` 验证定时器；`multi-instance/001-runtime.t` 验证两台真实容器。此结果不等于 Kubernetes 集群压力验收。
- HTTP 签名时间窗口为 300 秒，不保证窗口内恰好执行一次。
- 本地测试、镜像与配置验证不等于远程 GitHub Actions 已运行或生产已部署。
