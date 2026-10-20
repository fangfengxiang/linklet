# v0.2 升级操作手册

面向负责 PostgreSQL/OpenResty 发布的维护者。目标是保留历史短码、业务 Scene ID、AK/SK 密文及发号游标。本文不部署 React 后台，不设计浏览器登录。

## 发布门槛

本轮只在隔离数据库验证，不自动连接或切换生产库。

- 旧状态映射固定为：DomainEntry `1 active → 2 deployed`；`2 disabled / 3 deleted → 3 offline`，保留原 `deleted_at`。
- v0.2 Gateway 以 Scene 当前绑定域名为准。改绑后旧 Host 返回 404，新 Host 可解析同一码。先导出历史 Scene/域名与公开链接清单，确认业务接受这一行为，再安排维护窗口。没有域名快照，无法同时承诺旧、新域名均可用。
- 任何 Scene 缺少域名、越界 scene_id、非法配置值/过长配置键、悬空授权都应先修复；不得静默删除记录或清空授权绕过验收。
- 004 是在线兼容扩展。005 是停机切换，所有旧版本写入实例必须先停止。旧代码在 005 后不能继续运行，`sl_link` 兼容视图仅供运维 SQL 过渡使用。
- 暂留旧 `tenant_id`、`label`、序列 `id` 列及兼容加载入口，不再用于授权。删除属于后续独立 contract 版本。

## 备份和恢复演练

使用与服务端主版本匹配的 PostgreSQL 16 客户端。通过标准 PGHOST、PGPORT、PGDATABASE、PGUSER、PGPASSWORD 或 `.pgpass` 配置连接，不把密码写入命令历史。

```sh
bash scripts/backup_database.sh /secure/backups/linklet-before-v02
# 仅恢复到预先创建的隔离数据库；不要覆盖现有业务库
pg_restore --exit-on-error -d linklet_restore /secure/backups/linklet-before-v02/database.dump
psql -XAt -v ON_ERROR_STOP=1 -d linklet_restore -f scripts/database_snapshot.sql > /secure/backups/restored.json
cmp /secure/backups/linklet-before-v02/snapshot.json /secure/backups/restored.json
```

备份目录以 0700 权限创建，文件按 umask 077 保存，包含业务数据和加密凭证，需受控保存。另行备份原 AES-GCM 密钥；数据库备份无法替代密钥备份。快照包含完整 URL、短码、Scene ID、AK 和 current_max，不包含 SK 或密文。实际 dump 仍包含加密凭证。

## 扩展、核对、切换

已安装 001/003 的旧库，先执行 004；空库依次执行 001、003、004、005。002 是显式测试种子，不是生产迁移。每个脚本只执行一次，版本记录由发布系统维护。

```sh
psql -X -v ON_ERROR_STOP=1 -f migrations/004_v02_expand.sql
# 停止旧应用及所有写入作业，等待请求排空；再备份并保存切换前快照
psql -XAt -v ON_ERROR_STOP=1 -f scripts/database_snapshot.sql > /secure/backups/before-switch.json
psql -X -v ON_ERROR_STOP=1 -f migrations/005_v02_switch.sql
psql -XAt -v ON_ERROR_STOP=1 -f scripts/database_snapshot.sql > /secure/backups/after-switch.json
cmp /secure/backups/before-switch.json /secure/backups/after-switch.json
```

005 在锁内重新回填旧 Scene 的授权，避免扩展期间的旧写入遗漏；内部 `id` 新增，原 `scene_id` 不变；`sl_link` 表改名为 `sl_short_link`，保留兼容视图；`sequence_key` 成为主键，原 current_max 不重置。

核对七张基础表、外键、域名映射及每个旧 Scene 的 tenant.scene_ids 授权。新主键不改变旧业务标识。确认快照一致后再发布新应用，先小流量验证旧码跳转、共享管理、停用、过期、改绑及健康检查。监控数据库错误、HTTP 4xx/5xx 和缓存同步告警。

## 回退

004 后可继续使用旧应用；005 成功前的事务失败会整体回滚。005 成功后的状态语义、共享授权与新写入无法安全地随意 DOWN；优先前向修复。若必须恢复备份，应停止写入，恢复到独立数据库并核对后切流，同时明确备份之后的数据损失边界。不能只回滚镜像。

`make acceptance-docker` 在独立数据库验证旧 schema 回滚、历史数据迁移、扩展后旧写入补授权，以及 dump/restore 和快照一致性。它不代表生产备份已演练或历史域名清单已获业务确认。
