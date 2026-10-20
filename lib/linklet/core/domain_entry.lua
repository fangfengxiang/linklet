-- DNS hostname normalization shared by HTTP adapters; no transport dependencies.
local _M={}
function _M.normalize(host)
    if type(host)~="string" or host=="" then return nil end
    host=host:lower():gsub(":%d+$",""):gsub("%.$","")
    if host=="" or #host>253 or host:find("[^a-z0-9.%-]") or host:find("..",1,true) then return nil end
    for label in host:gmatch("[^.]+") do
        if #label>63 or not label:match("^[a-z0-9]") or not label:match("[a-z0-9]$") then return nil end
    end
    if host:sub(1,1)=="." then return nil end
    return host
end
return _M
