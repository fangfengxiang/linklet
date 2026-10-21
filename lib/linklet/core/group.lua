-- A group is a policy boundary; links remain independent aggregates.
local _M = {}
_M.__index = _M

function _M.new(repository)
    return setmetatable({repository = repository}, _M)
end

function _M:configure(id, domain_id, status)
    local group, err = self.repository:find_by_id(id)
    if err then return nil, err end
    if not group then return nil end
    if domain_id and tonumber(domain_id) ~= tonumber(group.domain_entry_id) and group.has_links then
        return nil, "group_domain_locked"
    end
    -- The database rechecks the invariant against concurrent inserts.
    return self.repository:configure(id, domain_id, status)
end
return _M
