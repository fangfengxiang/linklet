-- Linklet's stricter policy on top of the reusable SLDS domain.
local Lifecycle = require("slds.domain.lifecycle")
local _M = {namespace = "linklet"}

function _M.valid_target(url)
    return type(url) == "string" and #url > 0 and #url <= 2048 and
        url:match("^https?://[^/%s?#]+") ~= nil and not url:find("[%c%s]")
end

_M.lifecycle = {
    is_valid = function(status)
        return status == Lifecycle.ACTIVE or status == Lifecycle.DISABLED
    end,
    can_transition = function(from, to)
        return from == Lifecycle.ACTIVE and to == Lifecycle.DISABLED
    end,
    is_resolvable = Lifecycle.is_resolvable,
}

function _M.valid_disable(patch)
    if type(patch) ~= "table" or patch.status ~= Lifecycle.DISABLED then return false end
    for field in pairs(patch) do
        if field ~= "status" then return false end
    end
    return true
end
return _M
