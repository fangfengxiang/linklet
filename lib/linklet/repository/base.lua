-- lib/linklet/repository/base.lua
-- 模型基类：共享查询执行和行映射
-- Base model: shared query execution and row mapping

local setmetatable = setmetatable
local tostring = tostring
local error = error
local type = type

-- unpack 兼容 / unpack compatibility (Lua 5.1: unpack, Lua 5.3+: table.unpack)
local unpack = unpack or table.unpack

local _M = {}
_M.__index = _M

--- 创建模型基类实例 / Create base model instance
-- @param db 数据库实例（required）
-- @param table_name 表名
function _M.new(db, table_name)
    if not db then
        error("db is required", 2)
    end
    local self = setmetatable({}, _M)
    self.db = db
    self.table_name = table_name or ""
    return self
end

--- 执行查询 / Execute a query
-- @param sql SQL 语句
-- @param ... 参数
-- @return rows table or nil, err
function _M:query(sql, ...)
    return self.db:query(sql, ...)
end

--- 按条件查找 / Find by conditions
-- @param conditions WHERE 子句条件（如 "code = $1"）
-- @param params 参数值
-- @param limit 返回行数限制
-- @return rows or nil, err
function _M:find_where(conditions, params, limit)
    local sql = "SELECT * FROM " .. self.table_name
    if conditions and conditions ~= "" then
        sql = sql .. " WHERE " .. conditions
    end
    if limit then
        sql = sql .. " LIMIT " .. tonumber(limit)
    end
    if params then
        return self.db:query(sql, unpack(params))
    end
    return self.db:query(sql)
end

--- 按 ID 查找 / Find by primary key ID
-- @param id 主键 ID
-- @return row table or nil
function _M:find_by_id(id)
    local sql = "SELECT * FROM " .. self.table_name .. " WHERE id = $1 LIMIT 1"
    local res, err = self.db:query(sql, id)
    if not res then
        return nil, err
    end
    if res[1] then
        return res[1]
    end
    return nil
end

--- 插入行 / Insert a row
-- @param data 键值对表
-- @return inserted row or nil, err
function _M:insert(data)
    local cols = {}
    local vals = {}
    local ph = {}
    local i = 1
    for k, v in pairs(data) do
        cols[#cols + 1] = k
        vals[#vals + 1] = v
        ph[#ph + 1] = "$" .. i
        i = i + 1
    end
    local sql = "INSERT INTO " .. self.table_name ..
        " (" .. table.concat(cols, ", ") .. ")" ..
        " VALUES (" .. table.concat(ph, ", ") .. ")" ..
        " RETURNING *"
    local res, err = self.db:query(sql, unpack(vals))
    if not res then
        return nil, err
    end
    if res[1] then
        return res[1]
    end
    return nil
end

--- 更新行 / Update rows by condition
-- @param data 键值对表（要更新的字段）
-- @param condition WHERE 子句
-- @param params 条件参数
-- @return result or nil, err
function _M:update(data, condition, condition_params)
    local sets = {}
    local vals = {}
    local i = 1
    for k, v in pairs(data) do
        sets[#sets + 1] = k .. " = $" .. i
        vals[#vals + 1] = v
        i = i + 1
    end
    -- 合并条件参数
    local all_params = {}
    for j = 1, #vals do
        all_params[j] = vals[j]
    end
    if condition_params then
        if type(condition_params) == "table" then
            for j = 1, #condition_params do
                all_params[#all_params + 1] = condition_params[j]
            end
        else
            all_params[#all_params + 1] = condition_params
        end
    end
    -- 重新生成 SQL（条件参数从 vals 数量后开始编号）
    local set_clause = table.concat(sets, ", ")
    local sql = "UPDATE " .. self.table_name .. " SET " .. set_clause
    if condition and condition ~= "" then
        sql = sql .. " WHERE " .. condition
    end
    sql = sql .. " RETURNING *"
    return self.db:query(sql, unpack(all_params))
end

return _M
