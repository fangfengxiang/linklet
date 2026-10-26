-- One timer per instance polls an injected durable revision capability.
-- Healthy cache hits avoid storage I/O; stale synchronization bypasses cache.
local _M = {}
_M.__index = _M
function _M.new(revisions, cache, interval)
    assert(type(interval)=="number" and interval>0 and interval<math.huge,"invalid cache sync interval")
    assert(revisions and type(revisions.current_revision)=="function", "revision capability is required")
    cache.sync_window = interval * 2
    return setmetatable({revisions=revisions,cache=cache,interval=interval},_M)
end
function _M:tick()
    local checked_at = ngx.now()
    local value, err = self.revisions:current_revision()
    if value == nil then return nil, err or "revision unavailable" end
    local dict = self.cache:_get_dict()
    local revision = tostring(value)
    if dict:get("cache:revision") ~= revision then
        local generation = self.cache:generation() + 1
        dict:flush_all()
        dict:set("cache:generation", generation)
        dict:set("cache:revision", revision)
    end
    dict:set("cache:checked", checked_at)
    return true
end
function _M:start()
    if ngx.worker.id() ~= 0 then return true end
    local function poll(premature)
        if premature then return end
        local ok, err = self:tick()
        if not ok then ngx.log(ngx.WARN, "cache synchronization unavailable: ", err) end
    end
    assert(ngx.timer.at(0, poll))
    return ngx.timer.every(self.interval, poll)
end
return _M
