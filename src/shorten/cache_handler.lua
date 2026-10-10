-- src/shorten/cache_handler.lua
-- 缓存处理器：ngx.shared.DICT 缓存查找
-- Cache handler: ngx.shared.DICT cache lookup

local setmetatable = setmetatable
local pcall = pcall

local _M = {}
_M.__index = _M

function _M.new(cache)
    local self = setmetatable({}, _M)
    self.cache = cache
    return self
end

--- 缓存查找 / Cache lookup
-- 缓存命中时设置 ctx.target_url 并跳过后续数据库查询
-- @param ctx 请求上下文
-- @param next 下一个处理函数
function _M:handle(ctx, next)
    local code = ctx.params and ctx.params.code
    if not code then
        return next()
    end

    local cached = self.cache:get("link:" .. code)
    if cached then
        -- 缓存命中 / Cache hit
        ctx.target_url = cached
        ctx.cache_hit = true
        -- 直接跳到重定向（跳过 resolve_handler）
        -- 通过设置 ctx.resolved = true 标记
        ctx.resolved = true
        return next()
    end

    -- 缓存未命中，继续到 resolve_handler
    return next()
end

return _M
