-- PostgreSQL failures become stable storage error codes at this boundary.
local _M = {}
local stable = {
    group_domain_locked = true, domain_bound = true, domain_unavailable = true,
    invalid_grants = true, invalid_transition = true, invalid_change = true,
    invalid_reference = true, conflict = true, unavailable = true,
    sequence_exhausted = true,
    group_unavailable = true,
}
local patterns = {
    {"group with links cannot change", "group_domain_locked"},
    {"domain is still bound", "domain_bound"},
    {"domain must be deployed", "domain_unavailable"},
    {"grants must reference", "invalid_grants"},
    {"domain lifecycle must follow", "invalid_transition"},
    {"cannot be re-enabled", "invalid_transition"},
    {"immutable", "invalid_change"},
    {"duplicate key value", "conflict"},
    {"violates foreign key constraint", "invalid_reference"},
}

function _M.normalize(err)
    if err == nil then return nil end
    if type(err) == "string" and stable[err] then return err end
    -- Ignore DETAIL/CONTEXT data, which may contain user-controlled values.
    local message = tostring(err):match("^[^\r\n]+") or ""
    for _, entry in ipairs(patterns) do
        if message:find(entry[1], 1, true) then return entry[2] end
    end
    return "unavailable"
end
return _M
