-- lib/linklet/repository/tenant.lua
-- 租户模型：sl_tenant 数据访问
-- Tenant model: sl_tenant data access

local setmetatable = setmetatable

local BaseModel = require("linklet.repository.base")
local _M = setmetatable({}, {__index = BaseModel})
_M.__index = _M

function _M.new(db)
    local self = BaseModel.new(db, "sl_tenant")
    return setmetatable(self, _M)
end

--- 创建租户 / Create a tenant
-- @param name 租户名称
-- @return row or nil, err
function _M:create(name)
    local sql = "INSERT INTO sl_tenant (name, status) VALUES ($1, 1) RETURNING *"
    local res, err = self.db:query(sql, name)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 按 ID 查找 / Find by ID
function _M:find_by_id(id)
    local sql = "SELECT * FROM sl_tenant WHERE id = $1 LIMIT 1"
    local res, err = self.db:query(sql, id)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 查询所有租户 / Find all tenants
-- @param limit 返回数量
-- @return rows or nil, err
function _M:find_all(limit)
    limit = limit or 100
    local sql = "SELECT * FROM sl_tenant ORDER BY created_at DESC LIMIT $1"
    return self.db:query(sql, limit)
end

function _M:authorized(id,scene_id)
    local rows,err=self.db:query([[SELECT 1 FROM sl_tenant WHERE id=$1 AND status=1
        AND deleted_at IS NULL AND $2::bigint=ANY(scene_ids)]],id,scene_id)
    if not rows then return nil,err end
    return rows[1]~=nil
end
function _M:grant(id, scene_ids)
    local ids={}
    for i,v in ipairs(scene_ids) do ids[i]=tostring(v) end
    local rows,err=self.db:query([[UPDATE sl_tenant SET scene_ids=$2::bigint[],updated_at=NOW()
        WHERE id=$1 AND deleted_at IS NULL RETURNING *]],id,"{"..table.concat(ids,",").."}")
    return rows and rows[1],err
end
function _M:set_status(id,status)
    local rows,err=self.db:query([[UPDATE sl_tenant SET status=$2,updated_at=NOW()
        WHERE id=$1 AND deleted_at IS NULL RETURNING *]],id,status)
    return rows and rows[1],err
end
return _M
