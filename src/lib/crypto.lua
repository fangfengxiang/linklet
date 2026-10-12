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

return _M
