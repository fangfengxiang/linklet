-- lib/linklet/http/response.lua
-- HTTP 响应工具 / HTTP response utilities

local setmetatable = setmetatable
local tostring = tostring
local type = type
local pcall = pcall

local _M = {}
_M.__index = _M

-- 加载 cjson（可选，优先 cjson.safe）
local cjson_ok, cjson = pcall(require, "cjson.safe")
if not cjson_ok then
    cjson = nil
end

--- 创建响应实例 / Create response instance
function _M.new()
    return setmetatable({}, _M)
end

--- 发送 JSON 响应 / Send JSON response
-- @param status HTTP 状态码
-- @param body 表（将被 JSON 编码）
-- @return true
function _M:json(status, body)
    self.sent = true
    local ngx = ngx
    local ngx_ok = ngx ~= nil
    if ngx_ok then
        ngx.status = status
        ngx.header["Content-Type"] = "application/json; charset=utf-8"
        if cjson then
            ngx.say(cjson.encode(body))
        else
            -- 简易 JSON 编码 / simple JSON encoder fallback
            ngx.say(_M._encode_json(body))
        end
        return true
    end
    -- 非 OpenResty 环境：仅返回值供测试
    self._status = status
    self._body = body
    return true
end

--- 成功响应 / Success response
-- @param data 数据对象
-- @param status HTTP 状态码（default 200）
function _M:success(data, status)
    status = status or 200
    return self:json(status, {
        code = 0,
        message = "success",
        data = data,
    })
end

--- 错误响应 / Error response
-- @param code 错误码（非零）
-- @param message 错误消息
-- @param status HTTP 状态码（default 400）
function _M:error_response(code, message, status)
    status = status or 400
    return self:json(status, {
        code = code,
        message = message,
        data = cjson and cjson.null or nil,
    })
end

--- 404 响应 / Not found response
function _M:not_found(msg)
    return self:error_response(404, msg or "not found", 404)
end

--- 410 响应 / Gone response
function _M:gone(msg)
    return self:error_response(410, msg or "gone", 410)
end

--- 401 响应 / Unauthorized response
function _M:unauthorized(msg)
    return self:error_response(401, msg or "unauthorized", 401)
end

--- 403 响应 / Forbidden response
function _M:forbidden(msg)
    return self:error_response(403, msg or "forbidden", 403)
end

--- 500 响应 / Internal error response
function _M:internal_error(msg)
    return self:error_response(500, msg or "internal server error", 500)
end

--- 简易 JSON 编码（cjson 不可用时的后备）/ Simple JSON encoder fallback
function _M._encode_json(val)
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        return tostring(val)
    elseif t == "string" then
        return '"' .. val:gsub('[%z\1-\31\\"]', function(c) return string.format('\\u%04x', string.byte(c)) end) .. '"'
    elseif t == "table" then
        -- 检查是否是数组 / check if array
        local is_array = true
        local count = 0
        for k, _ in pairs(val) do
            count = count + 1
            if type(k) ~= "number" then
                is_array = false
                break
            end
        end
        if is_array and count > 0 then
            local parts = {}
            for i = 1, count do
                parts[#parts + 1] = _M._encode_json(val[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                parts[#parts + 1] = '"' .. tostring(k) .. '":' .. _M._encode_json(v)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

return _M
