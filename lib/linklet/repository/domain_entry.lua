local Errors = require("linklet.repository.errors")
local Base=require("linklet.repository.base")
local _M=setmetatable({},{__index=Base})
_M.__index=_M
function _M.new(db) return setmetatable(Base.new(db,"sl_domain_entry"),_M) end
function _M:create(domain,tag,description)
    local rows,err=self.db:query([[INSERT INTO sl_domain_entry(domain,tag,description)
        VALUES($1,$2,$3) RETURNING *]],domain,tag,description)
    return rows and rows[1],Errors.normalize(err)
end
function _M:find_by_domain(domain)
    local rows,err=self.db:query([[SELECT * FROM sl_domain_entry
        WHERE domain=$1 AND status=2 AND deleted_at IS NULL]],domain)
    return rows and rows[1],Errors.normalize(err)
end
function _M:deploy(id)
    local rows,err=self.db:query([[UPDATE sl_domain_entry SET status=2,enabled_at=NOW(),updated_at=NOW()
        WHERE id=$1 AND status=1 AND deleted_at IS NULL RETURNING *]],id)
    return rows and rows[1],Errors.normalize(err)
end
function _M:disable(id)
    -- The database trigger shares a domain row lock with group binding changes.
    local rows,err=self.db:query([[UPDATE sl_domain_entry SET status=3,disabled_at=NOW(),updated_at=NOW()
        WHERE id=$1 AND status=2 AND deleted_at IS NULL RETURNING *]],id)
    return rows and rows[1],Errors.normalize(err)
end
function _M:find_all(limit)
    local rows, err = self.db:query([[SELECT * FROM sl_domain_entry
        WHERE deleted_at IS NULL ORDER BY id LIMIT $1]],limit or 100)
    return rows, Errors.normalize(err)
end
return _M
