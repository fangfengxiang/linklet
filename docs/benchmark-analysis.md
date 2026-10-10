# Linklet 业界对标分析

> 跨语言调研先行——对标业界短链系统实现，形成设计判断和取舍。

## 一、短链系统领域分析

### 核心问题域

短链系统的本质是 **短码 → 目标地址** 的映射服务，围绕这一核心衍生出：

1. **发号器**：如何生成全局唯一的递增 ID
2. **短码编码**：如何将 ID 转换为紧凑、不可预测的短码
3. **解析路径**：如何高性能地完成短码 → 目标地址的查找和跳转
4. **生命周期管理**：如何管理短链的启用、停用、过期、删除

### 业界发号器方案对比

| 方案 | 代表项目 | 优势 | 劣势 | Linklet 选择 |
|------|---------|------|------|-------------|
| 数据库自增 ID | 传统短链 | 简单可靠 | 单点竞争 | ❌ 高并发瓶颈 |
| 数据库号段 | 美团 Leaf | 批量减少 DB 访问 | 号段浪费、重启丢号 | ✅ 适合 OpenResty |
| Snowflake | Twitter | 去中心化、高性能 | 时钟回拨问题 | ❌ 过度复杂 |
| Redis 原子计数 | 部分项目 | 高性能 | 依赖 Redis | ❌ 增加依赖 |

**选择理由**：号段模式平衡了性能和复杂度，OpenResty Worker 本地消耗号段减少 DB 访问，多 Worker 安全通过 PostgreSQL 原子更新保证。

### 短码编码方案对比

| 方案 | 代表项目 | 短码长度 | 可预测性 | 双射保证 | Linklet 选择 |
|------|---------|---------|---------|---------|-------------|
| Base62(ID) | 多数短链 | 6-7 位 | 高（连续可猜） | 是 | ❌ 可预测 |
| Hash 截断 | bit.ly | 不固定 | 低 | 否（碰撞） | ❌ 需重试 |
| 黄金比例混淆 + Base62 | Linklet 自研 | 6 位起 | 低 | 待修正 | ✅ 可控混淆 |
| Hashids | 开源库 | 可变 | 中 | 是 | ❌ 非自研 |

### 解析路径方案对比

| 方案 | 代表项目 | 缓存层 | 回源策略 | Linklet 选择 |
|------|---------|--------|---------|-------------|
| CDN + DB | bit.ly | CDN 边缘 | CDN miss → DB | ❌ 无 CDN |
| Redis + DB | 多数自建 | Redis | Redis miss → DB | ❌ 增加依赖 |
| ngx.shared.DICT + DB | OpenResty 系 | 进程内共享内存 | DICT miss → DB | ✅ 原生支持 |

**选择理由**：`ngx.shared.DICT` 是 OpenResty 原生能力，进程间共享，无需额外依赖。缓存未命中回源 PostgreSQL。

## 二、Lua 库设计对标

### 模块组织

| 标杆库 | 组织模式 | Linklet 应用 |
|--------|---------|-------------|
| lua-resty-http | `resty.http` 单模块 + `resty.http_const` 常量 | `linklet.*` 命名空间 |
| lua-resty-redis | `resty.redis` 单模块 + 连接池内嵌 | Model 层内嵌连接池管理 |
| pgmoon | `pgmoon` + `pgmoon.pool` + `pgmoon.util` | database.lua 封装 pool |
| lua-yar | `yar.*` 多模块分层 | `linklet.*` 分层 |

### OOP 模式

遵循 Lua 官方指导思想（Programming in Lua 第 16 章）：

```lua
-- 类级共享元表模式
local _M = {}
_M.__index = _M

-- 静态工厂方法用点号
function _M.new(opts)
    return setmetatable({}, _M)
end

-- 实例方法用冒号
function _M:handle(ctx, next)
    -- ...
end
```

### 错误处理分层

| 层级 | 错误返回形式 | 标杆 |
|------|------------|------|
| 内部模块 | `nil, err_string` | dkjson, lua-resty-http |
| 用户 API | `nil, err_table` | lua-resty-redis |
| 编程错误 | `error(msg, 2)` | lua-resty-redis 参数校验 |

### 标准库 local 化

```lua
local string, math, tonumber, type = string, math, tonumber, type
```

对标 Roberto Ierusalimschy 的 #1 性能建议，消除全局表查找开销。

## 三、产品对标

### Sink（Cloudflare 短链）

| 维度 | Sink | Linklet |
|------|------|---------|
| 运行时 | Cloudflare Workers | OpenResty |
| 存储 | D1 + KV | PostgreSQL + ngx.shared.DICT |
| 定位 | Serverless 短链产品 | 自托管多租户短链服务 |
| 统计 | Analytics Engine | 暂不实现 |
| 启发 | 产品完整度、定位清晰 | 架构差异建立价值 |

**核心启发**：
1. 把定位说清楚——Linklet 是自托管 OpenResty 短链服务。
2. 用架构差异建立价值——原生运行、显式 DI、可替换实现。
3. 部署和使用路径完整——README + 架构图 + 可运行示例 + 配置说明。
