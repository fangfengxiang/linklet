# 本地开发

运行时为 OpenResty/LuaJIT，数据库为 PostgreSQL 16（验收基线）。Lua 5.1/5.3 单元测试用于检查可移植逻辑，加密与 cosocket 以真实 OpenResty 为准。

## 隔离验收

安装 Docker，执行：

```sh
make acceptance-docker
```

验收镜像安装 Test::Nginx 0.32、busted、LuaCov 和 luacheck，并启动独立 PostgreSQL。结果和案例映射见 [acceptance.md](acceptance.md)。

## 本机工具

安装 OpenResty、Perl/prove、LuaRocks，再安装 `Test::Nginx`、pgmoon、LPeg、busted、LuaCov、luacheck。原生模块必须按 OpenResty 的 LuaJIT/Lua 5.1 ABI 编译，不能复用 Lua 5.3/5.5 的 `.so`。

```sh
cpanm Test::Nginx@0.32
luarocks install pgmoon 1.18.0-1
luarocks install busted
luarocks install luacov
luarocks install luacheck
```

使用独立 `linklet_test` 数据库：用户 `linklet`、密码 `acceptance_only`、端口 15432。依次执行 `001_init.sql`、`003_integrity.sql`、`004_v02_expand.sql` 和 `005_v02_switch.sql`；不把测试数据脚本当成生产迁移。

```sh
make test
make lint
make acceptance
make coverage
```

源码在 `lib/linklet/`，mock 单元测试在 `spec/`，真实运行时验收在 `test/nginx/`，基准在 `test/benchmark/`。

## 变更流程

修改 `openspec/changes/refactor-backend-v02/` 的需求和设计，给问题补负向验收分组，再修复实现，最后记录验收证据和任务状态。验收通过后才同步正式规格；规划文件齐全不代表功能已完成。

## 基准

```sh
make benchmark
resty --shdict 'benchmark_cache 10m' -I lib test/benchmark/resolution_bench.lua
```

这是算法和缓存 handler 微基准，不应当作线上 HTTP 吞吐或数据库性能结论。

## SLDS 依赖

首次本地运行先执行 `make deps`；Docker/CI 使用同一个固定源码修订。构造注入与策略测试见 [SLDS 集成契约](slds-integration.md)。
