-- lib/linklet/repository/credential.lua
-- 租户凭证模型：AK/SK 数据访问与加密
-- Tenant credential model: AK/SK access and encryption

local setmetatable = setmetatable

local Base = require("linklet.repository.base")
local Errors = require("linklet.repository.errors")
local _M = setmetatable({}, {__index = Base})
_M.__index = _M

local Crypto = require("linklet.crypto")
function _M.set_encryption_key(key)
    Crypto.configure(key)
end

function _M.new(db, crypto)
    local self = Base.new(db, "sl_tenant_credential")
    self.crypto = crypto or Crypto
    return setmetatable(self, _M)
end

--- 创建凭证 / Create a credential
-- @param tenant_id 租户 ID
-- @param access_key 访问密钥
-- @param secret_key 秘密密钥（明文，将被加密存储）
-- @return row or nil, err
function _M:create(tenant_id, access_key, secret_key)
    local encrypted_sk, eerr = self.crypto.encrypt(secret_key)
    if not encrypted_sk then return nil, Errors.normalize(eerr) end
    local sql = "INSERT INTO sl_tenant_credential " ..
        "(tenant_id, access_key, secret_key_enc, status) " ..
        "VALUES ($1, $2, $3, 1) RETURNING id, tenant_id, access_key, status, created_at"
    local res, err = self.db:query(sql, tenant_id, access_key, encrypted_sk)
    if not res then
        return nil, Errors.normalize(err)
    end
    return res[1]
end

--- 按 AK 查找凭证 / Find credential by access key
-- @param access_key 访问密钥
-- @return row (含解密后的 secret_key) or nil
function _M:find_by_access_key(access_key)
    local sql = [[SELECT c.* FROM sl_tenant_credential c JOIN sl_tenant t ON t.id = c.tenant_id
        WHERE c.access_key = $1 AND c.status = 1 AND t.status = 1 AND t.deleted_at IS NULL LIMIT 1]]
    local res, err = self.db:query(sql, access_key)
    if not res then
        return nil, Errors.normalize(err)
    end
    if not res[1] then
        return nil
    end
    local row = res[1]
    -- 解密 SK
    if row.secret_key_enc then
        local secret, derr = self.crypto.decrypt(row.secret_key_enc)
        if not secret then return nil, Errors.normalize(derr) end
        row.secret_key = secret
        row.secret_key_enc = nil  -- 不返回加密字段
    end
    return row
end

--- 禁用凭证 / Disable a credential
-- @param access_key 访问密钥
-- @return row or nil, err
function _M:disable(access_key)
    local sql = [[UPDATE sl_tenant_credential SET status=2, disabled_at=NOW(), updated_at=NOW()
        WHERE access_key=$1 AND status=1 RETURNING id]]
    local res, err = self.db:query(sql, access_key)
    if not res then
        return nil, Errors.normalize(err)
    end
    return res[1]
end

return _M
