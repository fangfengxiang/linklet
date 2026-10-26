local Errors = require("linklet.repository.errors")
local Base = require("linklet.repository.base")
local _M = setmetatable({}, {__index = Base})
_M.__index = _M
function _M.new(db)
    return setmetatable(Base.new(db, "sl_group"), _M)
end
function _M:create(group_id, name, domain_entry_id)
    local rows, err = self.db:query([[INSERT INTO sl_group(group_id,name,domain_entry_id)
        VALUES($1,$2,$3) RETURNING *]],group_id,name,domain_entry_id)
    return rows and rows[1], Errors.normalize(err)
end
function _M:find_by_id(id)
    local rows, err = self.db:query([[SELECT g.*, EXISTS(
        SELECT 1 FROM sl_short_link l WHERE l.group_id=g.group_id) AS has_links
        FROM sl_group g WHERE group_id=$1 AND deleted_at IS NULL]],id)
    return rows and rows[1], Errors.normalize(err)
end
function _M:find_by_id_with_domain(id)
    local rows, err = self.db:query([[SELECT s.*, d.domain,d.status AS domain_status FROM sl_group s
        JOIN sl_domain_entry d ON d.id=s.domain_entry_id
        WHERE s.group_id=$1 AND s.deleted_at IS NULL AND d.deleted_at IS NULL]],id)
    return rows and rows[1], Errors.normalize(err)
end
function _M:find_by_tenant(id, limit)
    local rows, err = self.db:query([[SELECT s.* FROM sl_group s JOIN sl_tenant t ON s.group_id=ANY(t.group_ids)
        WHERE t.id=$1 AND t.status=1 AND t.deleted_at IS NULL AND s.deleted_at IS NULL
        ORDER BY s.group_id LIMIT $2]],id,limit or 100)
    return rows, Errors.normalize(err)
end
function _M:configure(id, domain_id, status)
    local rows, err = self.db:query([[UPDATE sl_group SET domain_entry_id=COALESCE($2,domain_entry_id),
        status=COALESCE($3,status),updated_at=NOW() WHERE group_id=$1 AND deleted_at IS NULL RETURNING *]],
        id,domain_id,status)
    return rows and rows[1], Errors.normalize(err)
end
return _M
