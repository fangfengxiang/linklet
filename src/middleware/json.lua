-- src/middleware/json.lua
-- JSON 请求体解析中间件
-- JSON body parsing middleware

local setmetatable = setmetatable
local pcall = pcall

local _M = {}
_M.__index = _M

function _M.new()
    return setmetatable({}, _M)
end

--- JSON 解析中间件 / JSON parsing middleware
-- 解析请求体为 JSON 并存入 ctx.params
-- @param ctx 请求上下文
-- @param next 下一个处理函数
function _M:handle(ctx, next)
    if ctx.request then
        local body, err = ctx.request:json_body()
        if body then
            ctx.json_body = body
            ctx.params = ctx.request:all_params()
        end
        if not body then
            if ctx.response then ctx.response:error_response(4000, err, 400) end
            return nil, err
        end
    end
    return next()
end

return _M
