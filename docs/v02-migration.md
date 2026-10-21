# v0.2 升级操作手册

面向负责 PostgreSQL/OpenResty 发布的维护者。目标是保留历史短码、业务 ID、AK/SK 密文及发号游标；旧 Scene 通过独立 006 迁移更名为 Group，原 scene_id 数值成为 group_id。

## 发布门槛

本轮只在隔离数据库验证，不自动连接或切换生产库。

- 旧状态映射固定为：DomainEntry `1 active → 2 deployed`；`2 disabled / 3 deleted → 3 offline`，保留原 `deleted_at`。
- Group 存在任何短链后禁止改绑域名，含停用及过期短链；禁止通过软删除 Group 或域名绕过保护。空 Group 仍可改绑。006 不恢复此前已被改绑的历史 URL，发布前仍需核对历史域名清单。
- 任何 Scene 缺少域名、越界 scene_id、非法配置值/过长配置键、悬空授权都应先修复；不得静默删除记录或清空授权绕过验收。
- 004 是在线兼容扩展。005 是停机切换，所有旧版本写入实例必须先停止。旧代码在 005 后不能继续运行，`sl_link` 兼容视图仅供运维 SQL 过渡使用。
- 006 同样需要停机窗口；停止所有使用 Scene 表/字段的 API、Gateway 和写入作业。应用与调用方同时切换为 group_id/group_ids 以及 `/api/v1/admin/group/*`、`group_config/*`；旧 HTTP 字段和路径不提供别名。AK/SK 签名需按实际新请求体重新计算。
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

已安装 001/003 的旧库，先执行 004；空库依次执行 001、003、004、005、006。已经完成 005 的部署只执行 006。002 是显式测试种子，不是生产迁移。001–005 保持原样，每个脚本只执行一次，版本记录由发布系统维护。

```sh
psql -X -v ON_ERROR_STOP=1 -f migrations/004_v02_expand.sql
# 停止旧应用及所有写入作业，等待请求排空；再备份并保存切换前快照
psql -XAt -v ON_ERROR_STOP=1 -f scripts/database_snapshot.sql > /secure/backups/before-switch.json
psql -X -v ON_ERROR_STOP=1 -f migrations/005_v02_switch.sql
psql -XAt -v ON_ERROR_STOP=1 -f scripts/database_snapshot.sql > /secure/backups/after-switch.json
cmp /secure/backups/before-switch.json /secure/backups/after-switch.json
# 保持维护窗口，先保存 005 后的独立备份，再执行命名及不变量切换
bash scripts/backup_database.sh /secure/backups/linklet-before-group
psql -X -v ON_ERROR_STOP=1 -f migrations/006_group_contract.sql
psql -XAt -v ON_ERROR_STOP=1 -f scripts/database_snapshot.sql > /secure/backups/after-group.json
cmp /secure/backups/after-switch.json /secure/backups/after-group.json
```

005 在锁内重新回填旧 Scene 的授权，避免扩展期间的旧写入遗漏；内部 `id` 新增，原 `scene_id` 不变；`sl_link` 表改名为 `sl_short_link`，保留兼容视图；`sequence_key` 成为主键，原 current_max 不重置。

006 原值重命名 sl_scene→sl_group、sl_scene_config→sl_group_config、关联字段 scene_id→group_id、tenant.scene_ids→group_ids；外键、唯一约束和授权数组保持原值。业务号序列名称更新，但序列状态不变。旧约束/索引名称可能保留 scene 字样，不影响约束。sl_link 运维视图仍以 scene_id 暴露旧列，不能运行旧应用。

核对七张基础表、外键、域名映射、group_ids 授权、凭证密文和 current_max。已有短链的软删除 Group 会阻断 006，应人工核对修复后重试。确认快照一致后发布新应用，验证旧码跳转、共享管理、停用、过期、空 Group 改绑成功、有短链改绑返回 409 及健康检查。监控数据库错误、HTTP 4xx/5xx 和缓存同步告警。

## 回退

004 后可继续使用旧应用；005/006 各自事务失败会整体回滚。成功后的状态语义、共享授权、字段命名与新写入无法安全地随意 DOWN；优先前向修复。若必须恢复备份，应停止写入，恢复到独立数据库并核对后切流，同时明确备份之后的数据损失边界。不能只回滚镜像。

`make acceptance-docker` 在独立数据库验证旧 schema 回滚、历史数据迁移、扩展后旧写入补授权，以及 dump/restore 和快照一致性。它不代表生产备份已演练或历史域名清单已获业务确认。
