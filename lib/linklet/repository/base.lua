-- Shared repository construction and primary-key lookup only.
-- Business writes belong to the explicit repositories, not a generic model API.
local _M = {}
_M.__index = _M

function _M.new(db, table_name)
    assert(db, "db is required")
    return setmetatable({db = db, table_name = table_name}, _M)
end

function _M:find_by_id(id)
    local rows, err = self.db:query("SELECT * FROM " .. self.table_name .. " WHERE id=$1 LIMIT 1", id)
    return rows and rows[1], err
end
return _M
