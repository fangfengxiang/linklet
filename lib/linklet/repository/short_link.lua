-- lib/linklet/repository/short_link.lua
-- 短链模型：sl_short_link 数据访问
-- Link model: sl_short_link data access

local setmetatable = setmetatable
local tostring = tostring

local BaseModel = require("linklet.repository.base")
local _M = setmetatable({}, {__index = BaseModel})
_M.__index = _M

--- 创建 link 模型实例 / Create link model instance
function _M.new(db)
    local self = BaseModel.new(db, "sl_short_link")
    return setmetatable(self, _M)
end

--- 按短码查找 / Find link by short code
-- @param code 短码
-- @return row or nil
function _M:find_by_code(code)
    local sql = [[SELECT l.*, EXTRACT(EPOCH FROM l.expires_at) AS expires_epoch,
        d.domain, d.status AS domain_status, d.deleted_at AS domain_deleted_at
        FROM sl_short_link l JOIN sl_scene s ON s.scene_id=l.scene_id
        JOIN sl_domain_entry d ON d.id=s.domain_entry_id
        WHERE l.code=$1 LIMIT 1]]
    local res, err = self.db:query(sql, code)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 创建短链 / Create a short link
-- @param data {code, target_url, scene_id, expires_at?}
-- @return row or nil, err
function _M:create(data, tenant_id)
    if not data.code or not data.target_url or not data.scene_id then return nil,"missing required fields" end
    local sql = [[INSERT INTO sl_short_link(code,target_url,scene_id,status,expires_at)
        SELECT $1,$2,s.scene_id,1,$4::timestamptz FROM sl_scene s
        JOIN sl_domain_entry d ON d.id=s.domain_entry_id
        WHERE s.scene_id=$3 AND s.status=1 AND s.deleted_at IS NULL AND d.status=2
        AND d.deleted_at IS NULL AND ($5::bigint IS NULL OR EXISTS(SELECT 1 FROM sl_tenant t
            WHERE t.id=$5 AND t.status=1 AND t.deleted_at IS NULL AND s.scene_id=ANY(t.scene_ids)))
        RETURNING *]]
    local rows,err=self.db:query(sql,data.code,data.target_url,data.scene_id,data.expires_at,tenant_id)
    if not rows then return nil,err end
    return rows[1], not rows[1] and "scene or grant no longer available" or nil
end

--- 停用短链 / Disable a short link (set status=2)
-- @param code 短码
-- @return row or nil, err
function _M:disable(code, tenant_id)
    local sql = [[UPDATE sl_short_link l SET status=2, disabled_at=NOW()
        FROM sl_tenant t WHERE l.code=$1 AND l.status=1 AND t.id=$2
        AND t.status=1 AND t.deleted_at IS NULL AND l.scene_id=ANY(t.scene_ids) RETURNING l.*]]
    local res, err = self.db:query(sql, code, tenant_id)
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
    local sql = "SELECT * FROM sl_short_link WHERE scene_id = $1 ORDER BY created_at DESC LIMIT $2"
    return self.db:query(sql, scene_id, limit)
end

function _M:find_authorized(code,tenant_id)
    local rows,err=self.db:query([[SELECT l.* FROM sl_short_link l JOIN sl_tenant t
        ON l.scene_id=ANY(t.scene_ids) WHERE l.code=$1 AND t.id=$2 AND t.status=1
        AND t.deleted_at IS NULL]],code,tenant_id)
    return rows and rows[1],err
end
return _M
