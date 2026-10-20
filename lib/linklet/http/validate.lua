-- lib/linklet/http/validate.lua
-- 参数校验中间件
-- Parameter validation middleware

local setmetatable = setmetatable
local type = type

local _M = {}
_M.__index = _M

function _M.new()
    return setmetatable({}, _M)
end

--- 创建校验规则 / Create validation rules
-- @param rules 表 {field = {required=true, type="string", max_len=255}}
function _M.new_with_rules(rules)
    local self = setmetatable({}, _M)
    self.rules = rules or {}
    return self
end

--- 参数校验中间件 / Parameter validation middleware
-- @param ctx 请求上下文（含 request）
-- @param next 下一个处理函数
function _M:handle(ctx, next)
    local params = ctx.request and ctx.request:all_params() or {}
    ctx.params = params

    if self.rules then
        for field, rule in pairs(self.rules) do
            local value = params[field]
            if rule.required and (value == nil or value == "") then
                ctx.validation_error = "missing required field: " .. field
                if ctx.response then ctx.response:error_response(4000, ctx.validation_error, 400) end
                return nil, ctx.validation_error
            end
            if value ~= nil and rule.type then
                if rule.type == "string" and type(value) ~= "string" then
                    ctx.validation_error = field .. " must be a string"
                    if ctx.response then ctx.response:error_response(4000, ctx.validation_error, 400) end
                    return nil, ctx.validation_error
                end
                if rule.type == "number" and type(value) ~= "number" then
                    -- 尝试转换为数字
                    local num = (type(value) == "string" and tonumber(value)) or nil
                    if not num then
                        ctx.validation_error = field .. " must be a number"
                        if ctx.response then ctx.response:error_response(4000, ctx.validation_error, 400) end
                        return nil, ctx.validation_error
                    end
                    params[field] = num
                    value = num
                end
            end
            if rule.type == "number" and value and
                (value < 1 or value > 9007199254740991 or value ~= math.floor(value)) then
                if ctx.response then ctx.response:error_response(4000, field .. " must be a positive integer", 400) end
                return nil, "invalid integer"
            end
            if field == "target_url" and type(value) == "string" and
                (not value:match("^https?://[^/%s]+") or value:find("[%c%s]")) then
                if ctx.response then ctx.response:error_response(4000, "target_url must be an HTTP(S) URL", 400) end
                return nil, "invalid URL"
            end
            if value and rule.max_len and type(value) == "string" and #value > rule.max_len then
                ctx.validation_error = field .. " exceeds max length " .. tostring(rule.max_len)
                if ctx.response then ctx.response:error_response(4000, ctx.validation_error, 400) end
                return nil, ctx.validation_error
            end
        end
    end

    return next()
end

return _M
