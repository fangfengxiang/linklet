FROM openresty/openresty:alpine-fat AS dependencies
RUN apk add --no-cache build-base git \
    && luarocks install pgmoon 1.18.0-1 \
    && luarocks install lua-cjson 2.1.0.10-1
COPY dependencies/lua-slds.ref /app/dependencies/lua-slds.ref
COPY scripts/install_slds.sh /app/scripts/install_slds.sh
RUN sh /app/scripts/install_slds.sh

FROM openresty/openresty:alpine-fat AS runtime
RUN apk add --no-cache curl
COPY --from=dependencies /usr/local/openresty/luajit/share/lua/5.1/ /usr/local/openresty/luajit/share/lua/5.1/
COPY --from=dependencies /usr/local/openresty/luajit/lib/lua/5.1/ /usr/local/openresty/luajit/lib/lua/5.1/
COPY dependencies/lua-slds.ref /app/dependencies/lua-slds.ref
COPY lib/ /app/lib/
COPY api/ /app/api/
COPY conf/ /app/conf/
COPY conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY conf/conf.d/ /etc/nginx/conf.d/
COPY migrations/ /app/migrations/
COPY scripts/ /app/scripts/
WORKDIR /app
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=5 \
    CMD curl -sf http://127.0.0.1/health || exit 1
EXPOSE 80
CMD ["openresty", "-g", "daemon off;"]

FROM dependencies AS acceptance-dependencies
RUN apk add --no-cache perl perl-dev make gcc musl-dev postgresql16-client wget python3 bash curl \
    && wget --timeout=30 --tries=3 -qO /tmp/cpanm https://cpanmin.us \
    && perl /tmp/cpanm --notest Test::Nginx@0.32 \
    && rm /tmp/cpanm
RUN luarocks install busted || luarocks install busted || luarocks install busted
RUN luarocks install luacov || luarocks install luacov || luarocks install luacov
RUN luarocks install luacheck || luarocks install luacheck || luarocks install luacheck

FROM acceptance-dependencies AS acceptance
COPY --from=runtime /app/ /app/
WORKDIR /app
COPY .busted .luacov .luacheckrc Makefile linklet-scm-1.rockspec /app/
COPY spec/ /app/spec/
COPY test/ /app/test/
COPY README.md /app/
COPY docs/ /app/docs/
ENTRYPOINT []
CMD ["bash", "scripts/test_nginx.sh"]

# A plain docker build must produce the serving application, not the test runner.
FROM runtime AS production
