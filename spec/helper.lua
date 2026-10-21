-- spec/helper.lua
-- 测试辅助：设置 package.path，提供 mock 工具
-- Test helper: set package.path, provide mock utilities

-- 添加 src/ 到 package.path / Add src/ to package.path
local src_path = debug.getinfo(1, "S").source:match("@(.*/)") or "./"
package.path = package.path .. ";" .. src_path .. "../src/?.lua;" .. src_path .. "../src/?/init.lua"

--- 创建 mock 数据库 / Create mock database
-- @param query_result 查询返回值（表或函数）
local function mock_db(query_result)
    local result = {
        queries = {},       -- 记录所有查询 / log all queries
        query_count = 0,
    }
    result.query = function(self, sql, ...)
        self.query_count = self.query_count + 1
        self.queries[#self.queries + 1] = {sql = sql, args = {...}}
        if type(query_result) == "function" then
            return query_result(sql, ...)
        elseif type(query_result) == "table" then
            return query_result
        end
        return {{id = 1, code = "testcod", target_url = "https://example.com", group_id = 1, status = 1}}
    end
    result.exec = result.query
    result.disconnect = function() end
    return result
end

--- 创建 mock 缓存 / Create mock cache
local function mock_cache()
    local store = {}
    local result = {
        store = store,
    }
    result.get = function(self, key)
        return store[key]
    end
    result.set = function(self, key, value, ttl)
        store[key] = value
        return true
    end
    result.generation = function() return 0 end
    result.invalidate = function(self, code) store["link:" .. code] = nil; return true end
    result.delete = function(self, key)
        store[key] = nil
        return true
    end
    result.get_or_set = function(self, key, factory, ttl)
        if store[key] then
            return store[key]
        end
        local val = factory()
        store[key] = val
        return val
    end
    return result
end

--- 创建 mock 响应 / Create mock response
local function mock_response()
    local result = {
        _status = nil,
        _body = nil,
        _location = nil,
    }
    result.json = function(self, status, body)
        self._status = status
        self._body = body
        return true
    end
    result.success = function(self, data, status)
        return self:json(status or 200, {code = 0, message = "success", data = data})
    end
    result.error_response = function(self, code, message, status)
        return self:json(status or 400, {code = code, message = message, data = nil})
    end
    result.not_found = function(self, msg)
        return self:error_response(404, msg or "not found", 404)
    end
    result.gone = function(self, msg)
        return self:error_response(410, msg or "gone", 410)
    end
    result.unauthorized = function(self, msg)
        return self:error_response(401, msg or "unauthorized", 401)
    end
    result.internal_error = function(self, msg)
        return self:error_response(500, msg or "internal server error", 500)
    end
    return result
end

--- 创建 mock 请求 / Create mock request
local function mock_request(method, uri, params, headers)
    local result = {
        _method = method or "GET",
        _uri = uri or "/",
        _params = params or {},
        _headers = headers or {},
    }
    result.method = function(self) return self._method end
    result.uri = function(self) return self._uri end
    result.all_params = function(self) return self._params end
    result.param = function(self, key, default)
        local v = self._params[key]
        if v == nil then return default end
        return v
    end
    result.header = function(self, name)
        local lower = name:lower()
        for k, v in pairs(self._headers) do
            if k:lower() == lower then return v end
        end
        return nil
    end
    result.json_body = function(self)
        return self._params, nil
    end
    result.query_params = function(self)
        return self._params
    end
    return result
end

return {
    mock_db = mock_db,
    mock_cache = mock_cache,
    mock_response = mock_response,
    mock_request = mock_request,
}
