-- src/models/link.lua
-- 短链模型：sl_link 数据访问
-- Link model: sl_link data access

local setmetatable = setmetatable
local tostring = tostring

local BaseModel = require("models.base_model")
local _M = setmetatable({}, {__index = BaseModel})
_M.__index = _M

--- 创建 link 模型实例 / Create link model instance
function _M.new(db)
    local self = BaseModel.new(db, "sl_link")
    return setmetatable(self, _M)
end

--- 按短码查找 / Find link by short code
-- @param code 短码
-- @return row or nil
function _M:find_by_code(code)
    local sql = "SELECT * FROM sl_link WHERE code = $1 LIMIT 1"
    local res, err = self.db:query(sql, code)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 创建短链 / Create a short link
-- @param data {code, target_url, scene_id, expires_at?}
-- @return row or nil, err
function _M:create(data)
    if not data.code or not data.target_url or not data.scene_id then
        return nil, "missing required fields: code, target_url, scene_id"
    end
    if data.expires_at then
        local sql = "INSERT INTO sl_link (code, target_url, scene_id, status, expires_at) " ..
            "VALUES ($1, $2, $3, 1, $4) RETURNING *"
        local res, err = self.db:query(sql, data.code, data.target_url, data.scene_id, data.expires_at)
        if not res then
            return nil, err
        end
        return res[1]
    else
        local sql = "INSERT INTO sl_link (code, target_url, scene_id, status) " ..
            "VALUES ($1, $2, $3, 1) RETURNING *"
        local res, err = self.db:query(sql, data.code, data.target_url, data.scene_id)
        if not res then
            return nil, err
        end
        return res[1]
    end
end

--- 停用短链 / Disable a short link (set status=2)
-- @param code 短码
-- @return row or nil, err
function _M:disable(code)
    local sql = "UPDATE sl_link SET status = 2 WHERE code = $1 AND status = 1 RETURNING *"
    local res, err = self.db:query(sql, code)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 按场景查找 / Find links by scene
-- @param scene_id 场景 ID
-- @param limit 返回数量
-- @return rows or nil, err
function _M:find_by_scene(scene_id, limit)
    limit = limit or 100
    local sql = "SELECT * FROM sl_link WHERE scene_id = $1 ORDER BY created_at DESC LIMIT $2"
    return self.db:query(sql, scene_id, limit)
end

return _M
