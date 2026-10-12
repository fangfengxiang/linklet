-- src/models/tenant_credential.lua
-- 租户凭证模型：AK/SK 数据访问与加密
-- Tenant credential model: AK/SK access and encryption

local setmetatable = setmetatable
local tostring = tostring
local type = type
local pcall = pcall

-- Portable byte-wise operations for the standalone Lua test matrix.
local function bxor(a,b)
    local result, bit = 0, 1
    for _ = 1,8 do
        local left, right = a % 2, b % 2
        result = result + (left + right - 2 * left * right) * bit
        a, b, bit = math.floor(a/2), math.floor(b/2), bit*2
    end
    return result
end
local function bor(a,b) return (a + b + bxor(a,b)) / 2 end

local BaseModel = require("models.base_model")
local _M = setmetatable({}, {__index = BaseModel})
_M.__index = _M

local Crypto = require("lib.crypto")
function _M.set_encryption_key(key)
    Crypto.configure(key)
end

function _M.new(db)
    local self = BaseModel.new(db, "sl_tenant_credential")
    return setmetatable(self, _M)
end

--- 创建凭证 / Create a credential
-- @param tenant_id 租户 ID
-- @param access_key 访问密钥
-- @param secret_key 秘密密钥（明文，将被加密存储）
-- @return row or nil, err
function _M:create(tenant_id, access_key, secret_key)
    local encrypted_sk, eerr = _M._encrypt(secret_key)
    if not encrypted_sk then return nil, eerr end
    local sql = "INSERT INTO sl_tenant_credential " ..
        "(tenant_id, access_key, secret_key_enc, status) " ..
        "VALUES ($1, $2, $3, 1) RETURNING id, tenant_id, access_key, status, created_at"
    local res, err = self.db:query(sql, tenant_id, access_key, encrypted_sk)
    if not res then
        return nil, err
    end
    return res[1]
end

--- 按 AK 查找凭证 / Find credential by access key
-- @param access_key 访问密钥
-- @return row (含解密后的 secret_key) or nil
function _M:find_by_access_key(access_key)
    local sql = [[SELECT c.* FROM sl_tenant_credential c JOIN sl_tenant t ON t.id = c.tenant_id
        WHERE c.access_key = $1 AND c.status = 1 AND t.status = 1 LIMIT 1]]
    local res, err = self.db:query(sql, access_key)
    if not res then
        return nil, err
    end
    if not res[1] then
        return nil
    end
    local row = res[1]
    -- 解密 SK
    if row.secret_key_enc then
        local secret, derr = _M._decrypt(row.secret_key_enc)
        if not secret then return nil, derr end
        row.secret_key = secret
        row.secret_key_enc = nil  -- 不返回加密字段
    end
    return row
end

--- 禁用凭证 / Disable a credential
-- @param access_key 访问密钥
-- @return row or nil, err
function _M:disable(access_key)
    local sql = "UPDATE sl_tenant_credential SET status = 2 WHERE access_key = $1 AND status = 1 RETURNING id"
    local res, err = self.db:query(sql, access_key)
    if not res then
        return nil, err
    end
    return res[1]
end

--- HMAC 签名验证 / HMAC signature verification
-- @param secret_key 解密后的 SK
-- @param string_to_sign 待签名字符串
-- @param signature 客户端提供的签名
-- @return true/false
function _M.verify_signature(secret_key, string_to_sign, signature)
    if not secret_key or not string_to_sign or not signature then
        return false
    end
    -- 优先使用 ngx.hmac_sha1（OpenResty 环境）
    local ngx = ngx
    local ngx_ok = ngx ~= nil
    if ngx_ok and ngx.hmac_sha1 then
        local computed = ngx.hmac_sha1(secret_key, string_to_sign)
        -- 比较（使用恒定时间比较防止时序攻击）
        return _M._constant_time_compare(ngx.encode_base64(computed), signature)
    end
    -- 后备：使用 Lua 实现的 HMAC-SHA1
    -- 生产环境必须使用 ngx.hmac_sha1
    return false
end

_M._encrypt = Crypto.encrypt
_M._decrypt = Crypto.decrypt

--- 十六进制解码 / Hex decode
function _M._hex_decode(hex)
    if not hex or #hex % 2 ~= 0 then
        return nil
    end
    local result = {}
    for i = 1, #hex, 2 do
        local byte = tonumber(string.sub(hex, i, i + 1), 16)
        if not byte then
            return nil
        end
        result[#result + 1] = string.char(byte)
    end
    return table.concat(result)
end

--- 恒定时间比较 / Constant-time string comparison
function _M._constant_time_compare(a, b)
    if not a or not b then
        return false
    end
    if #a ~= #b then
        return false
    end
    if ngx then
        local ffi = require("ffi")
        ffi.cdef("int CRYPTO_memcmp(const void *a, const void *b, size_t len);")
        return ffi.C.CRYPTO_memcmp(a,b,#a) == 0
    end
    local result = 0
    for i = 1, #a do
        result = bor(result, bxor(string.byte(a, i), string.byte(b, i)))
    end
    return result == 0
end

return _M
