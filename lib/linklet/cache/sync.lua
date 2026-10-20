-- One timer per instance polls a durable PostgreSQL revision. Requests never
-- query PostgreSQL on a healthy cache hit. Stale synchronization bypasses cache.
local _M = {}
_M.__index = _M
function _M.new(db, cache, interval)
    assert(type(interval)=="number" and interval>0 and interval<math.huge,"invalid cache sync interval")
    cache.sync_window = interval * 2
    return setmetatable({db=db,cache=cache,interval=interval},_M)
end
function _M:tick()
    local checked_at = ngx.now()
    local rows, err = self.db:query("SELECT cache_revision FROM sl_id_sequence WHERE sequence_key=1")
    if not rows or not rows[1] then return nil, err or "cache revision missing" end
    local dict = self.cache:_get_dict()
    local revision = tostring(rows[1].cache_revision)
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
