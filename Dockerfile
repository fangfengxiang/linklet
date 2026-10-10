# Dockerfile
# Linklet 多租户短链系统 / Multi-tenant short link system
# 基于 OpenResty 官方镜像 / Based on official OpenResty image

FROM openresty/openresty:alpine-fat

# 安装依赖 / Install dependencies
RUN apk add --no-cache \
    postgresql-client \
    postgresql-libs \
    build-base \
    && luarocks install pgmoon \
    && luarocks install lua-cjson \
    && apk del build-base \
    && apk add --no-cache curl bash openssl

# 复制项目文件 / Copy project files
COPY src/ /app/src/
COPY conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY conf/conf.d/ /etc/nginx/conf.d/
COPY scripts/ /app/scripts/
COPY migrations/ /app/migrations/

# 设置权限 / Set permissions
RUN chmod +x /app/scripts/e2e_test.sh \
    && mkdir -p /app/logs /app/run

WORKDIR /app

# 健康检查 / Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=5 \
    CMD curl -sf http://localhost:80/health || exit 1

EXPOSE 80

# 启动脚本：等待 PostgreSQL 就绪 → 执行迁移 → 种子数据 → 启动 OpenResty
CMD ["openresty", "-g", "daemon off;"]
