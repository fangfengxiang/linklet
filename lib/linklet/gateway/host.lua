local _M={}
_M.normalize=require("linklet.core.domain_entry").normalize
function _M.key(host,code)
    local normalized=_M.normalize(host)
    if not normalized or type(code)~="string" then return nil end
    return "link:"..normalized..":"..code
end
return _M
