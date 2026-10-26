-- Versioned AES-256-GCM envelopes. Only OpenResty provides the crypto runtime.
local _M = {}
local key

function _M.configure(hex)
    if type(hex) ~= "string" or #hex ~= 64 or hex:find("[^%x]") then
        error("LINKLET_ENCRYPTION_KEY must contain exactly 64 hexadecimal characters")
    end
    key = hex:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end)
end

local function runtime()
    if not key then return nil, "encryption key is not configured" end
    if not ngx then return nil, "OpenResty crypto runtime is required" end
    return require("resty.aes"), require("resty.random")
end

function _M.encrypt(plaintext)
    local aes, random = runtime()
    if not aes then return nil, random end
    local iv = random.bytes(12, true)
    if not iv then return nil, "secure randomness unavailable" end
    local cipher, err = aes:new(key, nil, aes.cipher(256, "gcm"), {iv=iv})
    if not cipher then return nil, err end
    local encrypted, eerr = cipher:encrypt(plaintext, "linklet:v1")
    if not encrypted then return nil, eerr end
    return "v1:" .. ngx.encode_base64(iv .. encrypted[2] .. encrypted[1])
end

function _M.decrypt(envelope)
    local aes, err = runtime()
    if not aes then return nil, err end
    if type(envelope) ~= "string" or envelope:sub(1,3) ~= "v1:" then
        return nil, "unsupported credential encryption; rotate legacy credentials"
    end
    local bytes = ngx.decode_base64(envelope:sub(4))
    if not bytes or #bytes < 28 then return nil, "invalid encrypted credential" end
    local cipher, cerr = aes:new(key, nil, aes.cipher(256, "gcm"), {iv=bytes:sub(1,12)})
    if not cipher then return nil, cerr end
    return cipher:decrypt(bytes:sub(29), bytes:sub(13,28), "linklet:v1")
end

function _M.random_key()
    if not ngx then return nil, "OpenResty crypto runtime is required" end
    local bytes = require("resty.random").bytes(32, true)
    if not bytes then return nil, "secure randomness unavailable" end
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

-- Standalone tests use portable byte operations; production uses OpenSSL.
local function bxor(a, b)
    local result, bit = 0, 1
    for _ = 1, 8 do
        local left, right = a % 2, b % 2
        result = result + (left + right - 2 * left * right) * bit
        a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
    end
    return result
end

function _M.constant_time_compare(a, b)
    if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
    if ngx then
        local ffi = require("ffi")
        ffi.cdef("int CRYPTO_memcmp(const void *a, const void *b, size_t len);")
        return ffi.C.CRYPTO_memcmp(a, b, #a) == 0
    end
    local result = 0
    for i = 1, #a do
        local different = bxor(a:byte(i), b:byte(i))
        result = (result + different + bxor(result, different)) / 2
    end
    return result == 0
end

function _M.verify_signature(secret_key, string_to_sign, signature)
    if type(secret_key) ~= "string" or secret_key == "" or
        type(string_to_sign) ~= "string" or string_to_sign == "" or
        type(signature) ~= "string" or signature == "" then return false end
    if not ngx or not ngx.hmac_sha1 then return false end
    local computed = ngx.encode_base64(ngx.hmac_sha1(secret_key, string_to_sign))
    return _M.constant_time_compare(computed, signature)
end

return _M
