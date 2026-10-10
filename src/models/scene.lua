-- src/models/scene.lua
-- 场景模型：sl_scene 数据访问
-- Scene model: sl_scene data access

local setmetatable = setmetatable

local BaseModel = require("models.base_model")
local _M = setmetatable({}, {__index = BaseModel})
_M.__index = _M

function _M.new(db)
    local self = BaseModel.new(db, "sl_scene")
    return setmetatable(self, _M)
end

--- 创建场景 / Create a scene
-- @param tenant_id 租户 ID
-- @param name 场景名称
-- @param domain_entry_id 域名入口 ID（可选）
-- @return row or nil, err
function _M:create(tenant_id, name, domain_entry_id)
    if domain_entry_id then
        local sql = "INSERT INTO sl_scene (tenant_id, name, domain_entry_id, status) " ..
            "VALUES ($1, $2, $3, 1) RETURNING *"
        local res, err = self.db:query(sql, tenant_id, name, domain_entry_id)
        if not res then
            return nil, err
        end
        return res[1]
    else
        local sql = "INSERT INTO sl_scene (tenant_id, name, status) " ..
            "VALUES ($1, $2, 1) RETURNING *"
        local res, err = self.db:query(sql, tenant_id, name)
        if not res then
            return nil, err
        end
        return res[1]
    end
end

--- 按 ID 查找场景（含域名入口信息）/ Find scene by ID with domain entry
-- @param scene_id 场景 ID
-- @return row (含 domain 和 tenant_id) or nil, err
function _M:find_by_id_with_domain(scene_id)
    local sql = [[
        SELECT s.scene_id, s.tenant_id, s.name, s.domain_entry_id, s.status,
               d.domain, d.label AS domain_label, d.status AS domain_status
        FROM sl_scene s
        LEFT JOIN sl_domain_entry d ON s.domain_entry_id = d.id
        WHERE s.scene_id = $1 AND s.status = 1
        LIMIT 1
    ]]
    local res, err = self.db:query(sql, scene_id)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 按租户查找场景列表 / Find scenes by tenant
-- @param tenant_id 租户 ID
-- @param limit 返回数量
-- @return rows or nil, err
function _M:find_by_tenant(tenant_id, limit)
    limit = limit or 100
    local sql = "SELECT * FROM sl_scene WHERE tenant_id = $1 AND status = 1 ORDER BY created_at DESC LIMIT $2"
    return self.db:query(sql, tenant_id, limit)
end

return _M
