-- src/models/tenant_credential.lua
-- 租户凭证模型：AK/SK 数据访问与加密
-- Tenant credential model: AK/SK access and encryption

local setmetatable = setmetatable
local tostring = tostring
local type = type
local pcall = pcall

-- 加载 bit 库 / Load bit library (LuaJIT bit, bit32, or Lua 5.3+ native operators)
local _bit
local ok_bit, mod = pcall(require, "bit")
if ok_bit then _bit = mod else
    local ok_bit32, mod32 = pcall(require, "bit32")
    if ok_bit32 then _bit = mod32 end
end
local bxor, bor
if _bit then
    bxor = _bit.bxor
    bor = _bit.bor
else
    -- Lua 5.3+ 原生位运算 / Lua 5.3+ native bitwise operators
    -- 使用 load 加载避免语法错误 / Use load to avoid syntax errors on Lua 5.1
    local _xor_ok, _xor_fn = pcall(load, "return function(a, b) return a ~ b end")
    local _bor_ok, _bor_fn = pcall(load, "return function(a, b) return a | b end")
    bxor = (_xor_ok and _xor_fn) and _xor_fn() or nil
    bor = (_bor_ok and _bor_fn) and _bor_fn() or nil
end

local BaseModel = require("models.base_model")
local _M = setmetatable({}, {__index = BaseModel})
_M.__index = _M

-- 加密密钥（生产环境应从配置注入）/ Encryption key
local encryption_key = "linklet-default-key-change-me"

--- 设置加密密钥 / Set encryption key
-- @param key 加密密钥（十六进制或字符串）
function _M.set_encryption_key(key)
    encryption_key = key
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
    local encrypted_sk = _M._encrypt(secret_key)
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
    local sql = "SELECT * FROM sl_tenant_credential WHERE access_key = $1 AND status = 1 LIMIT 1"
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
        row.secret_key = _M._decrypt(row.secret_key_enc)
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
    local ngx_ok, ngx = pcall(require, "ngx")
    if ngx_ok and ngx.hmac_sha1 then
        local computed = ngx.hmac_sha1(secret_key, string_to_sign)
        -- 比较（使用恒定时间比较防止时序攻击）
        return _M._constant_time_compare(ngx.encode_base64(computed), signature)
    end
    -- 后备：使用 Lua 实现的 HMAC-SHA1
    -- 生产环境必须使用 ngx.hmac_sha1
    return false
end

--- 简易加密 / Simple encryption (XOR-based, for demo)
-- 生产环境应使用 AES-256-CBC 或 PostgreSQL pgcrypto
function _M._encrypt(plaintext)
    local result = {}
    for i = 1, #plaintext do
        local key_char = string.byte(encryption_key, ((i - 1) % #encryption_key) + 1)
        local pt_char = string.byte(plaintext, i)
        result[#result + 1] = string.char(bxor(pt_char, key_char))
    end
    -- Base64 编码
    local ngx_ok, ngx = pcall(require, "ngx")
    if ngx_ok and ngx.encode_base64 then
        return ngx.encode_base64(table.concat(result))
    end
    -- 后备：十六进制编码
    local hex = ""
    for _, c in ipairs(result) do
        hex = hex .. string.format("%02x", string.byte(c))
    end
    return hex
end

--- 简易解密 / Simple decryption (XOR-based, for demo)
function _M._decrypt(ciphertext)
    local ngx_ok, ngx = pcall(require, "ngx")
    local decoded
    if ngx_ok and ngx.decode_base64 then
        decoded = ngx.decode_base64(ciphertext)
        if not decoded then
            -- 尝试十六进制解码
            decoded = _M._hex_decode(ciphertext)
        end
    else
        decoded = _M._hex_decode(ciphertext)
    end
    if not decoded then
        return nil
    end
    local result = {}
    for i = 1, #decoded do
        local key_char = string.byte(encryption_key, ((i - 1) % #encryption_key) + 1)
        local ct_char = string.byte(decoded, i)
        result[#result + 1] = string.char(bxor(ct_char, key_char))
    end
    return table.concat(result)
end

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
    local result = 0
    for i = 1, #a do
        result = bor(result, bxor(string.byte(a, i), string.byte(b, i)))
    end
    return result == 0
end

return _M
