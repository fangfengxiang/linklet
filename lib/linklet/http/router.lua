-- lib/linklet/http/router.lua
-- 路由器：路由匹配 + 中间件链
-- Router: route matching + middleware chain

local setmetatable = setmetatable
local tostring = tostring
local type = type
local error = error

local _M = {}
_M.__index = _M

--- 创建路由器 / Create router instance
function _M.new()
    local self = setmetatable({}, _M)
    self.routes = {}
    self.global_middleware = {}
    return self
end

--- 添加全局中间件 / Add global middleware
-- @param mw 中间件实例（需有 handle 方法）
function _M:use(mw)
    self.global_middleware[#self.global_middleware + 1] = mw
    return self
end

--- 注册路由 / Register a route
-- @param method HTTP 方法（"GET", "POST", "PUT", "DELETE"）
-- @param pattern 路径模式（支持 :param 占位，如 "/:code"）
-- @param handler 处理函数或中间件链
function _M:route(method, pattern, ...)
    local args = {...}
    assert(#args > 0, "route requires a terminal handler")
    local middleware_chain = {}
    for index = 1, #args - 1 do
        local middleware = args[index]
        assert(type(middleware) == "function" or
            (type(middleware) == "table" and type(middleware.handle) == "function"), "invalid middleware")
        middleware_chain[#middleware_chain + 1] = middleware
    end
    local handler = args[#args]
    assert(type(handler) == "function" or
        (type(handler) == "table" and type(handler.handle) == "function"), "invalid terminal handler")

    self.routes[#self.routes + 1] = {
        method = method:upper(),
        pattern = pattern,
        middleware = middleware_chain,
        handler = handler,
    }
    return self
end

--- 快捷方法 / Convenience methods
function _M:get(pattern, ...) return self:route("GET", pattern, ...) end
function _M:post(pattern, ...) return self:route("POST", pattern, ...) end
function _M:put(pattern, ...) return self:route("PUT", pattern, ...) end
function _M:delete(pattern, ...) return self:route("DELETE", pattern, ...) end

--- 匹配路由 / Match a route
-- @param method HTTP 方法
-- @param uri 请求 URI
-- @return route table with matched params, or nil
function _M:match(method, uri)
    method = method:upper()
    for _, route in ipairs(self.routes) do
        if route.method == method then
            local params, matched = self:_match_pattern(route.pattern, uri)
            if matched then
                return route, params
            end
        end
    end
    return nil, nil
end

--- 匹配路径模式 / Match URL pattern
-- 支持 :param 占位符
-- @param pattern 路径模式（如 "/:code" 或 "/api/v1/shorten/create"）
-- @param uri 实际路径
-- @return params table, matched boolean
function _M:_match_pattern(pattern, uri)
    local pattern_segments = self:_split_path(pattern)
    local uri_segments = self:_split_path(uri)

    if #pattern_segments ~= #uri_segments then
        return {}, false
    end

    local params = {}
    for i = 1, #pattern_segments do
        local ps = pattern_segments[i]
        local us = uri_segments[i]
        if ps:sub(1, 1) == ":" then
            -- 参数段 / parameter segment
            params[ps:sub(2)] = us
        elseif ps ~= us then
            return {}, false
        end
    end
    return params, true
end

--- 分割路径 / Split path into segments
function _M:_split_path(path)
    local segments = {}
    for seg in path:gmatch("[^/]+") do
        segments[#segments + 1] = seg
    end
    return segments
end

--- 分发请求 / Dispatch request
-- @param ctx 请求上下文（含 method, uri, request, response 等）
-- @return handler result or nil, err
function _M:dispatch(ctx)
    local route, params = self:match(ctx.method, ctx.uri)
    if not route then
        if ctx.response then
            ctx.response:not_found("route not found")
        end
        return nil, "route not found"
    end

    ctx.params = params
    -- 构建中间件链 / Build middleware chain
    local chain = {}
    -- 全局中间件 / global middleware
    for _, mw in ipairs(self.global_middleware) do
        chain[#chain + 1] = mw
    end
    -- 路由级中间件 / route-level middleware
    for _, mw in ipairs(route.middleware) do
        chain[#chain + 1] = mw
    end

    -- Functions and objects retain registration order; the final item terminates.
    local function invoke(value, next_handler)
        if type(value) == "function" then return value(ctx, next_handler) end
        return value:handle(ctx, next_handler)
    end
    local function run(index)
        if index > #chain then return invoke(route.handler) end
        return invoke(chain[index], function() return run(index + 1) end)
    end
    return run(1)
end

return _M
