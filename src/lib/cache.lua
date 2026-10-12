-- src/lib/cache.lua
-- 缓存封装（ngx.shared.DICT）
-- Cache wrapper for ngx.shared.DICT

local setmetatable = setmetatable
local tostring = tostring
local type = type
local pcall = pcall

local _M = {}
_M.__index = _M

--- 创建缓存实例 / Create cache instance
-- @param dict_name ngx.shared.DICT 名称（default "linklet_cache"）
-- @return cache 实例
function _M.new(dict_name)
    local self = setmetatable({}, _M)
    self.dict_name = dict_name or "linklet_cache"
    self.dict = nil  -- 延迟初始化 / lazy init
    return self
end

--- 获取 ngx.shared.DICT / Get the shared dict
-- 在 OpenResty 环境下从 ngx.shared 获取
-- 在测试环境下从注入的 mock 获取
function _M:_get_dict()
    if self.dict then
        return self.dict
    end
    local ngx = ngx
    local ngx_ok = ngx ~= nil
    if ngx_ok and ngx.shared then
        self.dict = ngx.shared[self.dict_name]
    end
    return self.dict
end

--- 设置缓存注入 / Set cache dict injection (for testing)
-- @param dict 模拟的 shared dict
function _M:set_dict(dict)
    self.dict = dict
end

--- 获取缓存值 / Get cached value
-- @param key 缓存键
-- @return value or nil
function _M:get(key)
    local dict = self:_get_dict()
    if not dict then
        return nil
    end
    if self.sync_window and key:sub(1,5) == "link:" then
        local checked = dict:get("cache:checked")
        if not checked or ngx.now() - checked > self.sync_window then return nil end
    end
    return dict:get(key)
end

--- 设置缓存值 / Set cached value
-- @param key 缓存键
-- @param value 缓存值（字符串）
-- @param ttl 过期时间（秒，可选）
-- @return true or nil, err
function _M:set(key, value, ttl)
    local dict = self:_get_dict()
    if not dict then
        return nil, "cache not available"
    end
    if type(value) ~= "string" then
        value = tostring(value)
    end
    if ttl then
        return dict:set(key, value, ttl)
    else
        return dict:set(key, value)
    end
end

--- 删除缓存值 / Delete cached value
-- @param key 缓存键
function _M:delete(key)
    local dict = self:_get_dict()
    if not dict then
        return nil, "cache not available"
    end
    dict:delete(key)
    return true
end

-- A generation guards against an in-flight lookup refilling a disabled entry.
function _M:generation()
    local dict = self:_get_dict()
    return dict and dict:get("cache:generation") or 0
end
function _M:invalidate(code)
    local dict = self:_get_dict()
    if not dict then return nil, "cache not available" end
    dict:incr("cache:generation", 1, 0)
    dict:delete("link:" .. code)
    return true
end

--- 获取或设置 / Get or set pattern
-- 缓存未命中时调用 factory 函数获取值并写入缓存
-- @param key 缓存键
-- @param factory 缓存未命中时的取值函数，返回 value 或 nil, err
-- @param ttl 过期时间（秒，可选）
-- @return value or nil, err
function _M:get_or_set(key, factory, ttl)
    local value = self:get(key)
    if value ~= nil then
        return value
    end
    local val, ferr = factory()
    if not val then
        return nil, ferr
    end
    self:set(key, val, ttl)
    return val
end

return _M
