local _M = {}
_M.__index = _M
function _M.new(db)
    return setmetatable({db = db}, _M)
end
function _M:list(group_id)
    return self.db:query("SELECT * FROM sl_group_config WHERE group_id=$1 ORDER BY config_key",group_id)
end
function _M:set(group_id, key, value, description)
    local rows, err = self.db:query([[INSERT INTO sl_group_config(group_id,config_key,config_value,description)
        VALUES($1,$2,$3,$4) ON CONFLICT(group_id,config_key) DO UPDATE SET
        config_value=EXCLUDED.config_value,description=EXCLUDED.description,updated_at=NOW() RETURNING *]],
        group_id, key, value, description)
    return rows and rows[1], err
end
function _M:delete(group_id, key)
    local rows, err = self.db:query("DELETE FROM sl_group_config WHERE group_id=$1 AND config_key=$2 RETURNING id",
        group_id, key)
    return rows and rows[1], err
end
return _M
