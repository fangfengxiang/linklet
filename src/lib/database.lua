-- Per-query pgmoon connections; OpenResty cosocket keepalive provides the pool.
local _M = {}
_M.__index = _M

function _M.new(opts)
    assert(opts and opts.database, "opts.database is required")
    return setmetatable({config={
        host=opts.host or "127.0.0.1", port=opts.port or 5432,
        database=opts.database, user=opts.user or "postgres", password=opts.password or "",
        pool_size=opts.max_pool_size or 10, backlog=opts.backlog or 100,
        ssl=opts.ssl, ssl_verify=opts.ssl_verify,
    }, timeout=opts.timeout or 5000, idle_timeout=opts.idle_timeout or 60000}, _M)
end

function _M:_new_conn()
    local conn = require("pgmoon").new(self.config)
    conn:settimeout(self.timeout)
    local ok, err = conn:connect()
    if not ok then
        pcall(conn.disconnect, conn)
        return nil, err
    end
    return conn
end

function _M:_release(conn, healthy)
    if healthy and ngx and conn.keepalive then
        local ok = conn:keepalive(self.idle_timeout, self.config.pool_size)
        if ok then return end
    end
    pcall(conn.disconnect, conn)
end

local function interpolate(conn, sql, ...)
    local n, params = select("#", ...), {...}
    return (sql:gsub("%$(%d+)", function(index)
        local i = tonumber(index)
        assert(i >= 1 and i <= n, "missing SQL parameter")
        local value = params[i]
        if value == nil then return "NULL" end
        if type(value) == "number" then
            assert(value == value and math.abs(value) < math.huge, "invalid numeric SQL parameter")
            return tostring(value)
        end
        if type(value) == "boolean" then return value and "TRUE" or "FALSE" end
        assert(type(value) == "string", "SQL parameters must be scalar values")
        return assert(conn:escape_literal(value))
    end))
end

function _M:query(sql, ...)
    local conn, err = self:_new_conn()
    if not conn then return nil, err end
    local ok, statement = pcall(interpolate, conn, sql, ...)
    if not ok then self:_release(conn, false); return nil, statement end
    local success, result, qerr = pcall(conn.query, conn, statement)
    self:_release(conn, success and result ~= nil)
    if not success then return nil, result end
    return result, qerr
end

function _M:transaction(fn)
    local conn, err = self:_new_conn()
    if not conn then return nil, err end
    local begun, berr = conn:query("BEGIN")
    if not begun then self:_release(conn, false); return nil, berr end
    local ok, result, ferr = pcall(fn, conn)
    if not ok or result == nil or result == false then
        local rolled = conn:query("ROLLBACK")
        self:_release(conn, rolled ~= nil)
        return nil, ok and ferr or result
    end
    local committed, cerr = conn:query("COMMIT")
    self:_release(conn, committed ~= nil)
    if not committed then return nil, cerr end
    return result
end

function _M:exec(sql) return self:query(sql) end
function _M:close() end
return _M
