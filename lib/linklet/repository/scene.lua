local Base = require("linklet.repository.base")
local _M = setmetatable({}, {__index=Base})
_M.__index = _M
function _M.new(db) return setmetatable(Base.new(db,"sl_scene"),_M) end
function _M:create(scene_id, name, domain_entry_id)
    local rows,err=self.db:query([[INSERT INTO sl_scene(scene_id,name,domain_entry_id)
        VALUES($1,$2,$3) RETURNING *]],scene_id,name,domain_entry_id)
    return rows and rows[1],err
end
function _M:find_by_id(id)
    local rows,err=self.db:query("SELECT * FROM sl_scene WHERE scene_id=$1 AND deleted_at IS NULL",id)
    return rows and rows[1],err
end
function _M:find_by_id_with_domain(id)
    local rows,err=self.db:query([[SELECT s.*, d.domain,d.status AS domain_status FROM sl_scene s
        JOIN sl_domain_entry d ON d.id=s.domain_entry_id
        WHERE s.scene_id=$1 AND s.deleted_at IS NULL AND d.deleted_at IS NULL]],id)
    return rows and rows[1],err
end
function _M:find_by_tenant(id,limit)
    return self.db:query([[SELECT s.* FROM sl_scene s JOIN sl_tenant t ON s.scene_id=ANY(t.scene_ids)
        WHERE t.id=$1 AND t.status=1 AND t.deleted_at IS NULL AND s.deleted_at IS NULL
        ORDER BY s.scene_id LIMIT $2]],id,limit or 100)
end
function _M:configure(id,domain_id,status)
    local rows,err=self.db:query([[UPDATE sl_scene SET domain_entry_id=COALESCE($2,domain_entry_id),
        status=COALESCE($3,status),updated_at=NOW() WHERE scene_id=$1 AND deleted_at IS NULL RETURNING *]],
        id,domain_id,status)
    return rows and rows[1],err
end
return _M
