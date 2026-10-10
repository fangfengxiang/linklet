## Why

当前需要一个基于 OpenResty + Lua + PostgreSQL 的多租户短链系统，支持短链创建/解析/停用全生命周期、多租户 AK/SK 鉴权、场景化域名管理。现有 Lua 生态缺乏可生产使用的自托管短链方案（lua-resty-shortlink 仅原型级），Linklet 填补这一空白。

参考设计文档 `docs/design.md` 中的全部架构决策。

## What Changes

- **新增短码生成模块**：黄金比例混淆（`0x9E377B97F4A7C15`）+ Base62 编码，生成 ≥6 位不可预测短码
- **新增发号器模块**：PostgreSQL 号段批量分配，Worker 本地消耗，支持多 Pod 并发安全
- **新增解析网关**：`ngx.shared.DICT` 缓存 → PostgreSQL 回源 → HTTP 302 跳转
- **新增管理 API**：`POST /shorten/create`、`POST /shorten/gen`、`PUT /shorten/disable`，统一 JSON 响应
- **新增多租户鉴权**：AK/SK + HMAC 签名，SK 加密存储，认证只做一次
- **新增数据模型**：5 张核心表（sl_link, sl_tenant, sl_scene, sl_domain_entry, sl_scene_config），关联链 短链→场景→域名记录→租户
- **新增基础设施**：pgmoon 连接池封装、ngx.shared.DICT 缓存封装、Router + Middleware + Handler 架构
- **新增测试体系**：busted BDD 单元测试 + 功能测试 + E2E 测试 + 基准测试
- **新增 CI/CD**：GitHub Actions（luacheck + busted + coverage + Docker 构建 + 镜像推送）
- **新增部署**：Dockerfile（OpenResty 基础镜像）+ Kubernetes YAML

## Capabilities

### New Capabilities

- `short-code-gen`: 短码生成算法——黄金比例混淆 + Base62 编码，保证 ≥6 位、不可预测、全局唯一（数据库约束兜底）
- `id-generator`: 发号器——PostgreSQL 号段批量分配，Worker 本地消耗，多 Pod 并发安全，允许跳号
- `resolution-gateway`: 解析网关——缓存优先（ngx.shared.DICT）→ 数据库回源 → 状态/过期检查 → HTTP 302 跳转
- `management-api`: 管理 API——短链创建/生成/停用，统一 JSON 响应格式，场景授权校验
- `tenant-auth`: 多租户鉴权——AK/SK + HMAC 签名，SK 加密存储，认证一次后请求上下文传递
- `data-model`: 数据模型——5 张核心表，关联链隔离，短码全局唯一，状态不可逆，域名记录不可修改
- `infrastructure`: 基础设施——pgmoon 连接池、缓存封装、Router/Middleware/Handler、统一响应/请求工具
- `testing-ci`: 测试与 CI/CD——busted BDD、luacov 覆盖率、luacheck lint、GitHub Actions 全流程、Docker/K8s 部署

### Modified Capabilities

（无——初始项目，无已有 spec 需修改）

## Impact

- **新增代码**：`src/` 下全部 Lua 源码（~15 模块），`spec/` 下 BDD 测试，`test/` 下 E2E/基准测试
- **新增配置**：nginx.conf、conf.d/default.conf、.luacheckrc、rockspec、Dockerfile、K8s YAML
- **依赖**：pgmoon（PostgreSQL 驱动）、lua-cjson（JSON 编解码）、busted（测试）、luacov（覆盖率）、luacheck（lint）
- **数据库**：PostgreSQL，5 张表 + 迁移脚本
- **运行时**：OpenResty（ngx.socket, ngx.shared.DICT, cosocket）
- **CI/CD**：GitHub Actions（test.yml, benchmark.yml, docs.yml, release.yml）

### Rollback Plan

- 代码回滚：`git revert` 即可，无外部服务依赖变更
- 数据库回滚：迁移脚本提供 down 版本（DROP TABLE）
- 部署回滚：K8s `kubectl rollout undo deployment/linklet`
- 镜像回滚：使用前一版本 image tag
