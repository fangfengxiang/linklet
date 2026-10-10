# Linklet 短链系统设计文档

> 本文档基于 ChatGPT 对话（讨论短链系统方案）的设计讨论总结，结合业界短链域设计思想与 Lua 优秀类库设计原则。

## 一、系统定位

Linklet 是一个基于 **OpenResty + Lua + PostgreSQL** 的多租户短链系统。

### 产品范围

| 模块 | 职责 |
|------|------|
| 管理 API | 短链创建、修改、失效；多租户 AK/SK 鉴权 |
| 解析网关 | 短码解析 → HTTP 302 跳转 |
| 租户与凭证 | 租户管理、AK/SK 配置 |
| 场景与域名 | 业务场景配置、域名入口管理 |

### 设计原则

1. **OpenResty 原生**：利用 Nginx 请求处理能力 + Lua 灵活性，不引入额外 Web 框架。
2. **显式依赖注入**：依赖通过构造参数注入，不把 Context 当作依赖查找器。
3. **Lua-native**：优先 Lua 模块、表、函数和显式调用，不为形式抽象增加不必要层次。
4. **读路径优先**：解析路径极致快速（缓存优先），写入可靠。
5. **边界清晰**：领域逻辑与基础设施分离，缓存和数据库实现可替换。

## 二、数据模型

### 核心实体关系

```
sl_tenant（租户）
    ↓ scene_ids
sl_scene（场景）
    ↓ domain_entry_id
sl_domain_entry（域名记录）
    ↑
sl_link（短链）→ scene_id → sl_scene
```

**关键设计**：短链只记录 `scene_id`，不冗余 `tenant_id` 或 `domain_id`。租户隔离沿关联链实现：

```
短链 → 场景 → 域名记录 → 租户
```

### 表结构

#### sl_link — 短链核心表

| 字段 | 语义 | 约束 |
|------|------|------|
| `id` | 数据库记录身份 | 主键，自增 |
| `code` | 面向用户的短码标识 | 全局唯一，创建后不可变 |
| `target_url` | 目标地址 | 创建后不可修改 |
| `scene_id` | 所属业务场景 | 外键 → sl_scene |
| `status` | 生命周期状态 | 1=启用, 2=停用 |
| `created_at` | 创建时间 | |
| `expires_at` | 过期时间 | 允许为空 |

**业务不变量**：
- 短码全局唯一（数据库约束保证）
- 删除后短码永久不可复用（逻辑删除）
- 停用后不可重新启用（状态不可逆）
- 过期是时间条件，不需要额外状态字段

#### sl_tenant — 租户表

管理租户及其关联的场景集合（通过 `scene_ids` 关联）。

#### sl_scene — 场景表

| 字段 | 语义 |
|------|------|
| `scene_id` | 稳定不可变的场景标识 |
| `name` | 场景名称 |
| `description` | 场景描述 |
| `domain_entry_id` | 关联的域名记录 |

#### sl_domain_entry — 域名入口表

| 字段 | 语义 | 约束 |
|------|------|------|
| `domain` | 域名字符串 | 唯一，需规范化 |
| `label` | 标签 | |
| `description` | 描述 | |
| `status` | 状态 | |
| `created_at` | 创建时间 | |
| `updated_at` | 更新时间 | |
| `enabled_at` | 启用时间 | |
| `disabled_at` | 停用时间 | |
| `deleted_at` | 删除时间 | 逻辑删除标记 |

**关键约束**：域名记录创建后不可修改。

#### sl_scene_config — 场景配置表

场景级配置，通过 `scene_id` 关联场景。

### 建模决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 域名与短链关系 | 场景绑定域名 | 一个场景绑定一个域名记录 ID |
| 短码唯一性范围 | 全局唯一 | 数据库唯一索引保证 |
| 场景与短链关系 | 必须关联 | 每条短链必须属于一个场景 |
| 目标 URL 可变性 | 不可修改 | 创建后冻结 |
| 删除策略 | 逻辑删除 | 短码永久不可复用 |
| 状态流转 | 不可逆 | 停用/删除是终态 |

## 三、短码生成算法

### 算法概述

采用**黄金比例混淆 + Base62 编码**两阶段方案：

```
发号器 → incrID（自增正整数）
    ↓
GoldenSectionObfuscate(incrID) → 离散数值
    ↓
EncodeToBase62(obfuscated) → 短码字符串（≥6 位）
```

### 黄金比例混淆

- **常数**：`goldenRatio = 0x9E377B97F4A7C15`（(√5-1)/2 × 2^64 的整数近似，奇数）
- **原理**：奇数与 2^64 互质，模 2^64 乘法严格双射
- **分段设计**：不同分段的输出区间互不重叠
- **基础偏移**：`baseOffset = 62^5`，保证 Base62 编码后至少 6 位

### 碰撞问题与修正

**已知缺陷**：算法保留乘积高 32 位，丢弃低 32 位。截断操作丢失信息，不能继承完整乘法的双射性质。

**修正方向**：
- 必须保证同一分段内高 32 位映射无重复
- 数据库仍需对 `sl_link.code` 施加唯一约束（算法无冲突 ≠ 数据库不需要约束）

### Base62 编码

字符集：`0-9a-zA-Z`（62 字符），将混淆后的数值编码为紧凑字符串。

## 四、发号器设计

### 定位

发号器是**独立的号码分配机制**，不负责生成短码、不负责判断短链是否存在。

### 设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| ID 用途 | 直接作为 sl_link.id | 简化写入流程 |
| 发号方式 | 号段批量分配 | 减少数据库访问，适合高性能场景 |
| 跳号策略 | 允许跳号 | 只要求唯一不重复，进程重启浪费可接受 |

### 职责矩阵

| 职责 | 保证 |
|------|------|
| 号码空间 | 生成正整数，不重复分配 |
| 并发安全 | 多 Pod 同时申请不重叠 |
| 号码持久化 | 重启后不从旧位置重新发号 |
| 号段分配 | 批量发号号段互不重叠 |
| 容量边界 | 不超过算法和字段范围 |

### 实现方案

PostgreSQL 号段发号：数据库一次分配一批连续 ID，OpenResty 在本地消耗，减少每次创建短链的数据库访问。

## 五、架构设计

### 解析链路

```
GET /:code
    ↓
Router
    ↓
CacheHandler
    ├── 缓存命中 ──────────────┐
    └── 缓存未命中              │
         ↓                     │
    ResolveHandler             │
         ├── 查询数据库         │
         ├── 检查短链状态       │
         ├── 检查过期时间       │
         └── 写入缓存           │
         ↓                     │
    RedirectHandler ←──────────┘
         ↓
    HTTP 302
```

**关键点**：缓存命中不能直接结束请求，而是跳过数据库解析继续执行重定向。

### 管理 API 链路

```
POST /shorten/create
    ↓
Nginx（shorten.conf）
    ↓
认证层（lib/auth.lua）— AK/SK 验签
    ↓
Controller — 校验参数与场景授权
    ↓
Link Model — 创建短链记录
    ↓
返回 code
```

```
POST /shorten/gen
    ↓
（共用 create 逻辑）
    ↓
根据 scene_id 查询场景与域名
    ↓
拼接 short_url = domain + "/" + code
    ↓
返回 code + short_url
```

### 项目目录结构

```
linklet/
├── conf/
│   ├── nginx.conf
│   └── conf.d/
│       └── default.conf
├── src/
│   ├── app.lua
│   ├── router.lua
│   ├── routes.lua
│   ├── middleware/
│   │   ├── json.lua
│   │   ├── validate.lua
│   │   └── auth.lua
│   ├── shorten/
│   │   ├── handler.lua
│   │   ├── cache_handler.lua
│   │   ├── resolve_handler.lua
│   │   └── redirect_handler.lua
│   ├── lib/
│   │   ├── database.lua
│   │   ├── cache.lua
│   │   ├── request.lua
│   │   └── response.lua
│   └── models/
│       ├── base_model.lua
│       ├── tenant.lua
│       ├── tenant_credential.lua
│       ├── scene.lua
│       ├── domain_entry.lua
│       └── link.lua
├── migrations/
├── spec/
├── test/
├── scripts/
├── deploy/
│   └── k8s/
├── docs/
├── .github/
│   └── workflows/
├── Dockerfile
├── Makefile
├── linklet-scm-1.rockspec
├── .luacheckrc
├── LICENSE
└── README.md
```

### 组件职责

| 组件 | 职责 |
|------|------|
| Router | 匹配请求，调度 Middleware + Handler |
| CacheHandler | 缓存读取（ngx.shared.DICT） |
| ResolveHandler | 数据库解析短码，检查状态/过期，写入缓存 |
| RedirectHandler | 统一 HTTP 302 跳转 |
| Auth Middleware | AK/SK 解析、签名验证、凭证状态检查 |
| Link Model | PostgreSQL sl_link 数据访问 |
| Database | pgmoon 连接池封装 |

## 六、API 设计

### 管理 API

| 方法 | 路径 | 功能 |
|------|------|------|
| `POST` | `/shorten/create` | 创建短链，返回 code |
| `POST` | `/shorten/gen` | 创建短链，返回 code + short_url |
| `PUT` | `/shorten/disable` | 停用短链 |
| `GET` | `/admin/links` | 查询短链列表 |
| `GET` | `/admin/links/:code` | 查询单条短链 |
| `POST` | `/v1/tenants` | 创建租户 |
| `GET` | `/v1/tenants` | 查询租户列表 |
| `POST` | `/v1/credentials` | 创建 AK/SK |
| `POST` | `/v1/scenes` | 创建场景 |
| `POST` | `/v1/domains` | 创建域名记录 |

### 解析 API

| 方法 | 路径 | 功能 |
|------|------|------|
| `GET` | `/:code` | 解析短码并 302 跳转 |

### 统一响应格式

```json
{
    "code": 0,
    "message": "success",
    "data": {
        "code": "aB9xK2",
        "short_url": "https://s.example.com/aB9xK2"
    }
}
```

### 认证

- AK/SK + HMAC 签名
- SK 加密存储，验签时解密
- 认证只做一次，后续通过请求上下文传递已验证的租户信息

## 七、缓存策略

- **缓存介质**：OpenResty `ngx.shared.DICT`（进程内共享内存）
- **缓存内容**：短码 → 解析结果（target_url, status）
- **TTL**：可配置，默认 300 秒
- **失效**：短链状态变更时主动失效
- **一致性**：缓存未命中时回源数据库，成功后写入缓存

## 八、部署架构

### Docker

- 基础镜像：OpenResty 官方镜像
- 镜像只含运行时内容（OpenResty + LuaJIT + 项目代码 + Nginx 配置）
- 测试工具不进入生产镜像

### Kubernetes

| 资源 | 用途 |
|------|------|
| Deployment | 多 Pod 运行短链服务 |
| Service | 集群内访问入口 |
| ConfigMap | 非敏感配置 |
| Secret | 数据库凭证、加密密钥 |
| Ingress | 域名流量入口 |

### CI/CD

```
代码检查 → luacheck
    ↓
单元测试 → busted --coverage
    ↓
覆盖率检查 → luacov + threshold
    ↓
构建 Docker 镜像
    ↓
镜像验证 → 启动容器健康检查
    ↓
推送镜像仓库 → GHCR
    ↓
部署 Kubernetes → 更新 Deployment
```

## 九、业界参考

### 短链系统设计参考

| 项目 | 参考价值 |
|------|---------|
| Sink (Cloudflare) | 产品完整度、定位清晰度、部署体验 |
| lua-resty-shortlink | Lua 生态短链实现 |
| Twitter Snowflake | 分布式 ID 生成方案 |
| Hashids | 可逆编码方案 |
| bit.ly | 工业级短链架构 |

### Lua 库设计参考

| 项目 | 参考价值 |
|------|---------|
| lua-resty-http | OpenResty 模块组织、连接池管理 |
| lua-resty-redis | 连接池、错误处理模式 |
| pgmoon | PostgreSQL 访问、协程安全连接池 |
| lua-yar | 测试体系、CI/CD、rockspec 管理 |
| dkjson | 编码/解码不对称错误处理 |

### spec-kit 文档思考

从对话中提炼的工程化方法论：

1. **设计先行**：先明确职责边界、核心业务流程和运行时架构，再冻结设计。
2. **分阶段讨论**：系统定位 → 核心流程 → 运行时架构 → 工程化与扩展。
3. **决策显式化**：每个设计选择都列出选项和理由，不隐式假设。
4. **不过度工程化**：初期不引入 SLDS/Repository 等额外抽象层，保持简单直接。
5. **领域不变量优先**：短码唯一性、永久不复用、不可逆状态流转优先确认。

## 十、测试策略

### 测试分层

| 层级 | 工具 | 覆盖范围 |
|------|------|---------|
| 单元测试 | busted (BDD) | 短码算法、Base62 编码、模型逻辑 |
| 功能测试 | busted | API 端到端、解析流程 |
| 集成测试 | busted + mock | 数据库交互、缓存一致性 |
| E2E 测试 | OpenResty + Docker | 完整解析链路、并发 |
| 基准测试 | 自建脚本 | 短码生成性能、解析吞吐 |

### CI 矩阵

| 环境 | Lua 版本 | 说明 |
|------|---------|------|
| 标准测试 | Lua 5.1, LuaJIT 2.1, Lua 5.3 | 多版本兼容 |
| OpenResty | LuaJIT (OpenResty) | cosocket + ngx.shared.DICT |
| E2E | Docker (OpenResty + PostgreSQL) | 完整链路 |
