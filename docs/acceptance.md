# Linklet 验收记录

验收方式：Test::Nginx::Socket::Lua 启动真实 OpenResty，以 TCP/HTTP 访问生产 `conf/locations.conf`，使用 pgmoon 连接隔离 PostgreSQL。busted 作为补充单元测试。测试不能接受“302 或 404 都算成功”，也不能忽略失败退出码。

## 需求、修复与验收对应

| 项目 | 对齐后的要求与修复 | 验收证据 |
|---|---|---|
| 号段边界 | 分配闭区间 `[old_max+1,new_max]`；无重复端点 | `001-id-generator.t` TEST 1 |
| Worker 协程 | 仅分配慢路径使用 semaphore；20 协程不重复 | `001-id-generator.t` TEST 2 |
| 短码容量 | 用户确认 32 位；16 位分段精确模乘；超限拒绝 | `001-id-generator.t` TEST 3–4 |
| 停用参数 | disable 只要求 code；重复停用返回 404 | `002-management.t` TEST 1 |
| 多租户停用 | UPDATE 按当前 tenant.group_ids 授权限定，未授权租户不能修改 | `002-management.t` TEST 2 |
| 参数及响应 | 参数错误 400、分组越权 403、JSON data:null | `002-management.t` TEST 3 |
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
| 数据不变量 | 当前绑定域名、状态、域名不可变、短码永久保留 | `005-database-models.t` TEST 3 |
| 健康检查 | readiness 查询数据库；liveness 独立 | `006-runtime-admin.t` TEST 1 |
| 管理后台 | 租户/安全凭证创建、列表、停用闭环 | `006-runtime-admin.t` TEST 2 |
| 包与模型 | linklet 包入口；显式 Repository 接口 | `006-runtime-admin.t` TEST 3 |
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

## v0.2 验收结果（2026-10-21）

最终 `make acceptance-docker` 全流程退出码为 0：

- Busted：143 项通过，无失败/错误；luacheck：74 个文件，0 警告、0 错误。
- 单实例 Test::Nginx：9 个文件、108 个断言通过，含两个真实 Worker。
- 多实例 Test::Nginx：1 个文件、3 个断言通过，真实生产镜像共享 ID、独立缓存失效。
- 项目源码合并覆盖率：94.66%，门槛仍为 80%；仅统计 lib/linklet，排除 OpenResty 第三方 lualib。
- 旧 001/003 正向与逆序回滚、004 扩展、005 切换、006 Group 迁移：通过；缺少域名会阻断切换且无部分状态转换。
- 历史短码/URL/Scene→Group ID/AK/current_max 快照一致，旧应用扩展期间新增 Group 获授权；七张基础表、旧域名映射及凭证密文保留：通过。
- PostgreSQL 16 dump/restore 到独立数据库、快照对比：通过。
- LuaRocks 真实安装及安装后的 require("linklet")、Core/Admin/Gateway 依赖边界检查：通过。
- OpenSpec `validate --all --strict`：10 项通过；OpenAPI YAML：23 条路径/操作，operationId 唯一且业务接口认证完整；部署/CI YAML 和文档链接检查通过。

新增 SDD 用例在 `008-v02-contracts.t`：

| 分组 | 证据 |
|---|---|
| 共享 Group 创建/读取/停用，撤权后拒绝管理 | TEST 1 |
| Host 隔离，Tenant/Group 停用后永久短链仍解析 | TEST 2 |
| 已有短链改绑拒绝、停用/到期仍冻结、软删除不可绕过 | TEST 3 |
| 域名生命周期、配置与授权管理 API、负向校验 | TEST 4 |
| 域名下线与并发 Group 绑定互斥 | TEST 5 |
| next_ids/allocate_segment 混合并发不重叠、游标不可回退 | TEST 6 |
| create/gen 过期输入一致拒绝、凭证不可原地修改/删除复用 | TEST 7 |
| 首次创建先提交则并发改绑被拒绝 | TEST 8 |
| 改绑先提交则 gen 返回插入事务确认的新域名 | TEST 9 |

## Review 修复记录

- pgmoon 成功返回的查询计数被误作错误：统一适配成功返回值，增加真实查询断言。
- 备份工具自动安装 PostgreSQL 18 客户端，与服务端 16 恢复不兼容：验收镜像固定客户端 16。
- lib/ 的宽泛覆盖率匹配误含第三方 lualib：明确限定项目路径，保留覆盖率门槛。
- Admin 直接依赖 Gateway Host 工具：提取纯 Core 域名规则，并加入依赖方向检查。
- 新代码误连旧/仅 expand 数据库：readiness 验证实际 sl_short_link 基础表和 sequence_key。
- 拒绝零/无穷 TTL 与无效同步周期，避免零 TTL 导致缓存永久保留、绕过业务到期时间。
- 补齐迁移前悬空授权、历史域名格式检查，防止静默切换；所有已部署迁移文件保持不变。

历史基线为 143 项单测、75+3 个运行时断言、90.68% 覆盖率。v0.2 本次证据来自隔离测试，不代表生产部署或生产历史域名兼容验收。线上流程见 [迁移手册](v02-migration.md)。

## 一致性与边界

- 正整数 ID 最大 4294967295。号段跨越上限会被拒绝；剩余不足一个号段时可调整段大小，不会回绕。
- 黄金比例混淆可逆，不提供密码学不可预测性；公开短码不是权限凭证。
- 同实例停用即时切换缓存 generation。默认跨实例同步窗口为 1 秒，属于有界传播；正在执行的旧请求可完成。定时器或数据库不可用时，同步过期会绕过缓存。
- `003-resolution.t` 验证独立 shared dict、TTL 和同步失败后的 DB 降级；`009-workers.t` 通过响应头中的真实进程 ID 验证两个 Worker 都停止重定向；`007-production-init.t` 验证定时器；`multi-instance/001-runtime.t` 验证两台真实容器。此结果不等于 Kubernetes 集群压力验收。
- HTTP 签名时间窗口为 300 秒，不保证窗口内恰好执行一次。
- 本地测试、镜像与配置验证不等于远程 GitHub Actions 已运行或生产已部署。

## Group 收敛补充

006 在空库初始化及历史数据升级路径验证七表结构、业务 ID、配置、授权、短码/URL、凭证密文及游标保留。已有短链的软删除分组阻断迁移，验证事务回滚后仍保持旧表名。001–005 保持原样。

新加入双 Worker 用例后，验收曾暴露两个测试基础设施问题：夹具重置修订号产生跨实例 ABA，现已在隔离夹具中保持修订号递增；多个 Worker 同时写 LuaCov 文件丢失统计，现已改为独立文件、退出后合并。80% 源码覆盖率门槛保持不变。删除通用 Model 写接口时移除对应的旧通用 CRUD 单测，业务约束继续由数据库和运行时用例验收。

平台管理继续限定内部网络；多实例测试从另一容器携带租户签名访问管理路径仍为 403。React 登录/BFF 未实现，后续方案见 [安全边界](admin-auth.md)。旧 require 转发和 sl_link 运维视图仍为迁移审计保留，不提供旧 Scene HTTP 字段或路径兼容。

## SLDS 与存储边界验收（2026-10-26）

固定已公开 SLDS 基线集成，未新增 payload 或数据库迁移。当前 PostgreSQL 约束、历史 ID/短码/凭证和游标保留；ctx 传调用身份，metadata.group_id 映射原生列。支持的 metadata 与严格生命周期子集见 [集成契约](slds-integration.md)。

- 单元测试：152 项通过。
- lint：53 个 Lua 文件零警告/错误；SQL 仅在 Repository/DB 的边界检查通过。
- 真实 OpenResty/PostgreSQL：9 个单实例文件、123 个断言通过；两实例测试 3 个断言通过。
- 合并项目源码覆盖率 95.14%，原 80% 门槛保持不变。
- 迁移、历史快照、dump/restore、安装包加载、认证、Group 绑定竞态和永久短码验收通过。
- 新验收包含 admin/gateway 角色隔离、Gateway 绕过 Admin Router、规范化解析、终态停用、共享授权、基础设施错误，以及最后一次缓存写入前的跨 Worker 停用。

独立 review 修复了三个问题：旧查询在 generation 检查后可能填入新代缓存；SLDS 适配器创建时可能忽略输入状态；创建提交后的额外 Group 读取可能造成已创建却返回失败。现分别使用捕获代号写入、严格创建态校验及调用局部事务结果视图。安装范围和 LuaRocks 工具选择也统一。

双 Worker 测试启用测试监听 socket 的 reuseport，继续要求两个真实进程的响应均被观察到，避免默认接收调度造成用例偶发失败；生产配置不受此测试选项影响。

以上来自隔离环境。远程 CI 结果以最终推送提交为准；Release 仅在版本 tag 触发，本次不发布 tag 或切换生产。
