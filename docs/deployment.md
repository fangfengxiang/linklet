# 部署与升级

## Docker 开发部署

生成并保存独立的加密密钥，然后启动服务：

```sh
export LINKLET_ENCRYPTION_KEY="$(openssl rand -hex 32)"
docker compose -f deploy/docker-compose.yml up --build -d
curl -f http://127.0.0.1:8080/health
```

Compose 的新数据库会执行 001、003。已有数据库不会重新执行初始化目录，必须先备份，再人工应用尚未执行的 003 增量迁移。启动时不生成测试凭证、不重置 ID。

| 环境变量 | 用途 | 默认 |
|---|---|---|
| PGHOST / PGPORT | PostgreSQL 地址 | 127.0.0.1 / 5432 |
| PGDATABASE / PGUSER / PGPASSWORD | 数据库凭证 | 需要按部署配置 |
| LINKLET_ENCRYPTION_KEY | AES-GCM 32 字节密钥的 64 位十六进制表示 | 必填 |
| SEGMENT_SIZE | 号段大小 | 1000 |
| CACHE_TTL | 最大缓存秒数 | 300 |
| CACHE_SYNC_INTERVAL | 修订号同步秒数 | 0.5 |
| PGPOOLSIZE | 每 Worker 的池容量 | 10 |

同实例停用即时失效，跨实例默认约 1 秒内传播。同步信息超时后绕过缓存；缓存 TTL 还受链接到期时间限制。

管理入口默认只允许 loopback。通过容器内请求或受控管理通道操作，不要把整个代理网段加入白名单。公网入口需要在部署层配置 TLS。

## Kubernetes

先配置数据库和真实 Secret，再应用模板：

```sh
kubectl apply -f deploy/k8s/configmap.yaml
kubectl apply -f deploy/k8s/secret.yaml
kubectl apply -f deploy/k8s/deployment.yaml
```

`secret.yaml` 是模板，必须替换数据库密码和加密密钥。部署前运行数据库迁移。liveness 使用 `/health/live`，readiness 使用查询数据库的 `/health`。

`replicas: 3` 可以共享数据库，但各 Pod 的缓存独立，通过修订号同步。配置文件静态验证和本地运行测试不能代替目标集群验收。

## 凭证升级

旧 XOR 密文不被新版本接受。配置并保存新加密密钥后，为旧租户重新签发 AK/SK，更新客户端，再停用旧凭证。不要自动使用仓库中的默认 XOR 密钥解密。

生成新密钥后不能随意替换：现有 AES-GCM 凭证依赖原密钥。更换密钥需要重新签发凭证或实施专门的密钥轮换迁移。

## 回滚

先备份数据库。在一次性数据库中可以依次运行 `003_integrity_down.sql`、`001_init_down.sql` 验证迁移逆序；001_down 会删除表，不用于保留业务数据的生产回滚。

应用回滚可使用前一镜像和 `kubectl rollout undo`，但旧版本无法读取新 AES-GCM 凭证。必须同时规划凭证兼容性和数据库约束，不能只回滚镜像后假定业务恢复。
