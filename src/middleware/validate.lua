-- src/middleware/validate.lua
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
                return nil, ctx.validation_error
            end
            if value and rule.type then
                if rule.type == "string" and type(value) ~= "string" then
                    ctx.validation_error = field .. " must be a string"
                    return nil, ctx.validation_error
                end
                if rule.type == "number" and type(value) ~= "number" then
                    -- 尝试转换为数字
                    local num = tonumber(value)
                    if not num then
                        ctx.validation_error = field .. " must be a number"
                        return nil, ctx.validation_error
                    end
                    params[field] = num
                end
            end
            if value and rule.max_len and type(value) == "string" and #value > rule.max_len then
                ctx.validation_error = field .. " exceeds max length " .. tostring(rule.max_len)
                return nil, ctx.validation_error
            end
        end
    end

    return next()
end

return _M
