-- Domain errors acquire HTTP semantics only at the Admin boundary.
local _M = {}
local mapping = {
    invalid_url = {4001, 400},
    invalid_group_id = {4002, 400},
    group_inactive = {4003, 404},
    group_forbidden = {4004, 403},
    domain_unavailable = {4005, 400},
    invalid_expiry = {4007, 400},
    unavailable = {500, 500},
}

function _M.respond(response, err)
    local mapped = mapping[err.kind] or mapping.unavailable
    return response:error_response(mapped[1], err.message, mapped[2])
end
return _M
