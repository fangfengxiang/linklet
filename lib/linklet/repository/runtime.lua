-- Durable operational capabilities. Callers never receive SQL rows or syntax.
local Errors = require("linklet.repository.errors")
local _M = {}
_M.__index = _M

function _M.new(db)
    assert(db and type(db.query) == "function", "database is required")
    return setmetatable({db = db}, _M)
end

function _M:reserve_segment(sequence_key, size)
    local rows, err = self.db:query([[UPDATE sl_id_sequence SET
        current_max=current_max+COALESCE($2::integer,step),updated_at=NOW()
        WHERE sequence_key=$1 AND current_max<=4294967295-COALESCE($2::integer,step)
        RETURNING (current_max-COALESCE($2::integer,step)+1)::text AS segment_start,
        current_max::text AS segment_end]], sequence_key, size)
    if not rows then return nil, Errors.normalize(err) or "unavailable" end
    if not rows[1] then return nil, "sequence_exhausted" end
    local first, last = tonumber(rows[1].segment_start), tonumber(rows[1].segment_end)
    if not first or not last or first < 1 or last < first or last > 4294967295 or
        first ~= math.floor(first) or last ~= math.floor(last) then
        return nil, "unavailable"
    end
    return {start = first, ["end"] = last}
end

function _M:current_revision()
    local rows, err = self.db:query([[SELECT cache_revision::text AS cache_revision
        FROM sl_id_sequence WHERE sequence_key=1]])
    if not rows or not rows[1] or rows[1].cache_revision == nil then
        return nil, Errors.normalize(err) or "unavailable"
    end
    local revision = tostring(rows[1].cache_revision)
    if not revision:match("^%d+$") then return nil, "unavailable" end
    return revision
end

function _M:health()
    local rows, err = self.db:query([[SELECT 1 AS ready FROM pg_class c
        WHERE c.oid=to_regclass('sl_short_link') AND c.relkind='r'
        AND to_regclass('sl_group') IS NOT NULL
        AND EXISTS(SELECT 1 FROM sl_id_sequence WHERE sequence_key=1)]])
    if not rows or not rows[1] then return nil, Errors.normalize(err) or "unavailable" end
    return true
end
return _M
