-- src/lib/database.lua
-- PostgreSQL 连接池封装（pgmoon）
-- PostgreSQL connection pool wrapper using pgmoon

local setmetatable = setmetatable
local tostring = tostring
local error = error
local type = type

local _M = {}
_M.__index = _M

--- 创建数据库实例 / Create database instance
-- @param opts 配置项
--   - host: PostgreSQL 主机（default "127.0.0.1"）
--   - port: 端口（default 5432）
--   - database: 数据库名
--   - user: 用户名
--   - password: 密码
--   - max_pool_size: 连接池大小（default 10）
-- @return database 实例
function _M.new(opts)
    if not opts or not opts.database then
        error("opts.database is required", 2)
    end
    local self = setmetatable({}, _M)
    self.config = {
        host = opts.host or "127.0.0.1",
        port = opts.port or 5432,
        database = opts.database,
        user = opts.user or "postgres",
        password = opts.password or "",
        max_pool_size = opts.max_pool_size or 10,
    }
    self.pool = nil  -- 延迟初始化连接池 / lazy init pool
    return self
end

--- 初始化连接池 / Initialize connection pool
-- 在非 OpenResty 环境下，使用 pgmoon 直接连接
-- 在 OpenResty 环境下，使用 pgmoon.pool.PostgresPool
function _M:_get_pool()
    if self.pool then
        return self.pool
    end
    -- 尝试加载 pgmoon
    local ok, pgmoon = pcall(require, "pgmoon")
    if not ok then
        error("pgmoon is required: " .. tostring(pgmoon), 2)
    end
    -- 检查是否有 OpenResty cosocket（ngx 变量存在）
    local ngx_ok = pcall(require, "ngx")
    if ngx_ok then
        -- OpenResty 环境：使用 pgmoon 连接（cosocket 兼容）
        self.pool = pgmoon
    else
        -- 非 OpenResty：使用 pgmoon 直接连接
        self.pool = pgmoon
    end
    return self.pool
end

--- 创建新连接 / Create a new connection
function _M:_new_conn()
    local pgmoon = self:_get_pool()
    if not pgmoon then
        self.last_error = "pgmoon module not available"
        return nil
    end
    local ok_new, conn = pcall(pgmoon.new, pgmoon, self.config)
    if not ok_new or not conn then
        self.last_error = "pgmoon.new failed: " .. tostring(conn)
        return nil
    end
    local ok, err = conn:connect()
    if not ok then
        self.last_error = err or "failed to connect to PostgreSQL"
        return nil
    end
    return conn
end

--- 执行查询 / Execute a query
-- @param sql SQL 语句（支持 $1, $2 参数占位）
-- @param ... 参数值
-- @return result table or nil, err
function _M:query(sql, ...)
    local conn = self:_new_conn()
    if not conn then
        local ok_ngx, ngx = pcall(require, "ngx")
        if ok_ngx and ngx.log then
            ngx.log(ngx.ERR, "DB connection failed: ", tostring(self.last_error), " config host=", tostring(self.config.host))
        end
        return nil, "failed to get database connection"
    end
    local n = select("#", ...)
    if n > 0 then
        -- 内插参数：用 escape_literal 转义后替换 $N 占位符
        -- pgmoon 某些版本对 table 参数处理不一致，改用直接转义更可靠
        local params = { ... }
        local final_sql = sql:gsub("%$(%d+)", function(num)
            local idx = tonumber(num)
            if idx and idx >= 1 and idx <= n then
                local val = params[idx]
                if val == nil then
                    return "NULL"
                elseif type(val) == "number" then
                    return tostring(val)
                elseif type(val) == "boolean" then
                    return val and "TRUE" or "FALSE"
                else
                    -- 字符串类型：用 pgmoon 的 escape_literal 转义
                    -- escape_literal 对字符串返回带引号的结果
                    if conn.escape_literal then
                        return conn:escape_literal(val)
                    end
                    -- 兜底：手动转义单引号 / Fallback: manual quote escaping
                    local escaped = tostring(val):gsub("'", "''")
                    return "'" .. escaped .. "'"
                end
            end
            return "$" .. num
        end)
        local res, err = conn:query(final_sql)
        conn:disconnect()
        if not res then
            local ok_ngx, ngx = pcall(require, "ngx")
            if ok_ngx and ngx.log then
                ngx.log(ngx.ERR, "DB query error: ", tostring(err), " SQL: ", final_sql:sub(1, 200))
            end
            return nil, err or "query failed"
        end
        return res
    end
    local res, err = conn:query(sql)
    conn:disconnect()
    if not res then
        return nil, err or "query failed"
    end
    return res
end

--- 执行事务 / Execute in transaction
-- @param fn 事务函数，接收 conn 参数，返回 result 或 nil, err
-- @return fn 的返回值或 nil, err
function _M:transaction(fn)
    local conn = self:_new_conn()
    if not conn then
        return nil, "failed to get database connection"
    end
    conn:query("BEGIN")
    local ok, res = pcall(fn, conn)
    if not ok then
        conn:query("ROLLBACK")
        conn:disconnect()
        return nil, res  -- res 是错误消息
    end
    conn:query("COMMIT")
    conn:disconnect()
    return res
end

--- 执行原始 SQL（仅用于迁移）/ Execute raw SQL (for migrations only)
-- @param sql SQL 语句
-- @return result or nil, err
function _M:exec(sql)
    return self:query(sql)
end

--- 关闭连接池 / Close the connection pool
function _M:close()
    -- pgmoon 连接是 per-request 的，不需要显式关闭池
    self.pool = nil
end

return _M
