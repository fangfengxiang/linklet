-- src/shorten/resolve_handler.lua
-- 解析处理器：数据库查询 + 状态/过期校验 + 缓存写入
-- Resolve handler: DB query + status/expiry validation + cache write

local setmetatable = setmetatable
local tostring = tostring
local pcall = pcall

local _M = {}
_M.__index = _M

function _M.new(deps)
    local self = setmetatable({}, _M)
    self.link_model = deps.link_model
    self.cache = deps.cache
    self.cache_ttl = deps.cache_ttl or 300  -- 默认 5 分钟
    return self
end

--- 解析处理 / Resolve handler
-- 如果 ctx.resolved 已为 true（缓存命中），直接跳过
-- 否则查询数据库，校验状态/过期，写入缓存
-- @param ctx 请求上下文
-- @param next 下一个处理函数
function _M:handle(ctx, next)
    -- 缓存已命中，跳过数据库查询
    if ctx.resolved then
        return next()
    end

    local code = ctx.params and ctx.params.code
    if not code then
        if ctx.response then
            ctx.response:not_found("missing code")
        end
        return nil, "missing code"
    end

    -- 查询数据库 / Query database
    local link, err = self.link_model:find_by_code(code)
    if not link then
        -- 调试日志：记录查询失败原因 / Debug log: record query failure reason
        local ok_ngx, ngx = pcall(require, "ngx")
        if ok_ngx and ngx.log then
            ngx.log(ngx.ERR, "find_by_code failed: code=", tostring(code), " err=", tostring(err))
        end
        if ctx.response then
            ctx.response:not_found("short link not found")
        end
        return nil, "not found"
    end

    -- 状态校验 / Status validation
    -- 1=active, 2=disabled
    local status = tonumber(link.status)
    if status == 2 then
        if ctx.response then
            ctx.response:gone("link disabled")
        end
        return nil, "disabled"
    end

    -- 过期校验 / Expiration check
    if link.expires_at then
        local now
        local ok, ngx = pcall(require, "ngx")
        if ok and ngx.time then
            now = ngx.time()
        else
            now = os.time()
        end
        -- pgmoon 返回的 expires_at 可能是字符串或时间戳
        local expires = link.expires_at
        if type(expires) == "string" then
            -- PostgreSQL TIMESTAMPTZ 格式，尝试解析
            -- 简单比较：如果是 ISO 格式字符串
            local ok_parse, ts = pcall(function()
                return ngx and ngx.parse_http_time(expires) or nil
            end)
            if ok_parse and ts and now > ts then
                if ctx.response then
                    ctx.response:gone("link expired")
                end
                return nil, "expired"
            end
        elseif type(expires) == "number" then
            if now > expires then
                if ctx.response then
                    ctx.response:gone("link expired")
                end
                return nil, "expired"
            end
        end
    end

    -- 解析成功 / Resolution successful
    ctx.target_url = link.target_url
    ctx.resolved = true

    -- 写入缓存 / Write to cache
    if self.cache then
        self.cache:set("link:" .. code, link.target_url, self.cache_ttl)
    end

    return next()
end

return _M
