# Linklet

基于 OpenResty + Lua + PostgreSQL 的自托管多租户短链服务。

- 创建、生成完整 URL、不可逆停用短链。
- AK/SK HMAC 鉴权，AES-256-GCM 加密存储 SK。
- 租户按 group_ids 授权，共享管理分组下的短链。
- PostgreSQL 号段分配，32 位精确混淆与 Base62 短码。
- 缓存优先解析，状态与过期检查，HTTP 302 跳转。
- Test::Nginx 在真实 OpenResty/PostgreSQL 中验收。

正整数 ID 容量为 4294967295，超限拒绝，不回绕。混淆算法可逆，短码不是授权令牌。

## 启动

```sh
export LINKLET_ENCRYPTION_KEY="$(openssl rand -hex 32)"
docker compose -f deploy/docker-compose.yml up --build -d
curl -f http://127.0.0.1:8080/health
```

加密密钥必须妥善保存，已有数据库需按 [部署指南](docs/deployment.md) 应用增量迁移。启动不会重置 ID 或注入测试凭证。

## API

| 方法 | 路径 | 功能 |
|---|---|---|
| GET | `/:code` | 解析并跳转 |
| POST | `/api/v1/shorten/create` | 创建短码 |
| POST | `/api/v1/shorten/gen` | 创建完整短链 |
| PUT | `/api/v1/shorten/disable` | 按当前 Group 授权停用短链 |
| POST / GET | `/api/v1/admin/tenant/create`、`/list` | 租户管理 |
| POST / PUT | `/api/v1/admin/credential/create`、`/disable` | 凭证管理 |
| GET | `/health`、`/health/live` | 就绪与存活检查 |

管理后台默认仅允许 loopback。新增域名、分组、配置和租户授权操作见 [OpenAPI 契约](api/openapi.yaml)。业务 API 需要签名；详细字段与示例见 [API 文档](docs/api.md)。

Group 有任何短链后冻结域名绑定；短码全局唯一，code、target_url、group_id 不可修改。Admin 与租户 API 的边界及 React 接入方案见 [认证设计](docs/admin-auth.md)。

短链领域语义复用 lua-slds，集成边界和固定依赖构建见 [SLDS 集成契约](docs/slds-integration.md)。支持 `LINKLET_ROLE=combined|admin|gateway`。

## 验收

```sh
make acceptance-docker  # 独立 OpenResty + PostgreSQL + Test::Nginx
make deps               # 安装固定修订的 lua-slds
make test               # 补充单元测试
make lint
```

完整的需求、问题、测试案例对应关系见 [验收记录](docs/acceptance.md)。合并源码覆盖率门槛为 80%；CI 不忽略失败。

## 目录

| 目录 | 内容 |
|---|---|
| lib/linklet/ | Core、Repository、Admin、Gateway 与基础设施 |
| conf/ | Nginx 生产配置与共享 locations |
| migrations/ | 初始、增量、测试数据和回滚 SQL |
| spec/ | busted 单元测试 |
| test/nginx/ | Test::Nginx 运行时验收 |
| test/benchmark/ | 算法与缓存微基准 |
| deploy/ | 开发/验收 Compose、Kubernetes 模板 |
| openspec/ | 本地规划工作区，Git 忽略；发布约定记录在 docs/ |
| docs/ | API、开发、部署、设计和验收说明 |

旧库升级须先阅读 [v0.2 迁移手册](docs/v02-migration.md)，不直接覆盖 001。

开发方式见 [开发指南](docs/development.md)。架构说明见 [设计文档](docs/design.md)。
