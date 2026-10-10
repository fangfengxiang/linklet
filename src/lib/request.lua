-- src/lib/request.lua
-- HTTP 请求工具 / HTTP request utilities

local setmetatable = setmetatable
local tostring = tostring
local type = type
local pcall = pcall

local _M = {}
_M.__index = _M

local cjson_ok, cjson = pcall(require, "cjson.safe")
if not cjson_ok then
    cjson = nil
end

--- 创建请求实例 / Create request instance
-- @param ngx ngx 对象（在 OpenResty 环境中传入）
function _M.new(ngx)
    local self = setmetatable({}, _M)
    self._ngx = ngx
    self._params = nil
    return self
end

--- 获取请求方法 / Get HTTP method
function _M:method()
    if self._ngx and self._ngx.req then
        return self._ngx.req.get_method()
    end
    return "GET"
end

--- 获取请求 URI / Get request URI
function _M:uri()
    if self._ngx and self._ngx.var then
        return self._ngx.var.uri
    end
    return "/"
end

--- 获取查询参数 / Get query parameters
-- @return table of query params
function _M:query_params()
    if self._ngx and self._ngx.req then
        return self._ngx.req.get_uri_args()
    end
    return {}
end

--- 解析请求体（JSON）/ Parse request body as JSON
-- @return parsed table or nil, err
function _M:json_body()
    if not self._ngx or not self._ngx.req then
        return nil, "no ngx context"
    end
    self._ngx.req.read_body()
    local body = self._ngx.req.get_body_data()
    if not body or body == "" then
        return nil, "empty body"
    end
    if cjson then
        local data, err = cjson.decode(body)
        if not data then
            return nil, "invalid JSON: " .. tostring(err)
        end
        return data
    end
    -- 简易 JSON 解析后备不适合生产，这里返回错误
    return nil, "cjson not available for JSON parsing"
end

--- 获取所有参数（查询参数 + JSON 体）/ Get all parameters
-- 查询参数优先级低于 JSON 体参数
-- @return table of all params
function _M:all_params()
    if self._params then
        return self._params
    end
    local params = {}
    -- 合并查询参数
    local q = self:query_params()
    for k, v in pairs(q) do
        params[k] = v
    end
    -- 合并 JSON 体参数（体优先）
    local body, err = self:json_body()
    if body then
        for k, v in pairs(body) do
            params[k] = v
        end
    end
    self._params = params
    return params
end

--- 获取单个参数 / Get a single parameter
-- @param key 参数名
-- @param default 默认值
-- @return parameter value or default
function _M:param(key, default)
    local params = self:all_params()
    local v = params[key]
    if v == nil then
        return default
    end
    return v
end

--- 获取请求头 / Get request header
-- @param name 头名称（不区分大小写）
-- @return header value or nil
function _M:header(name)
    if self._ngx and self._ngx.req then
        local headers = self._ngx.req.get_headers()
        -- Nginx header 名不区分大小写
        local lower = name:lower()
        for k, v in pairs(headers) do
            if k:lower() == lower then
                return v
            end
        end
    end
    return nil
end

--- 设置注入的 ngx（用于测试）/ Set injected ngx (for testing)
function _M:set_ngx(ngx)
    self._ngx = ngx
    self._params = nil
end

return _M
