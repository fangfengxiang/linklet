-- Exact 32-bit golden-ratio permutation; values are not access-control tokens.
local _M = {}
local MODULUS, GOLDEN, OFFSET = 4294967296,2654435769,916132832
local INVERSE = 340573321
local ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local function multiply32(value,multiplier)
    local low,high = value % 65536,math.floor(value/65536)
    return (low*multiplier + ((high*multiplier)%65536)*65536) % MODULUS
end
function _M.obfuscate(id)
    assert(type(id) == "number" and id >= 0 and id < MODULUS and id == math.floor(id),
        "id must be an integer in the unsigned 32-bit range")
    return multiply32(id,GOLDEN)+OFFSET
end
function _M.encode_base62(value)
    assert(type(value) == "number" and value >= 0 and value <= 9007199254740991 and
        value == math.floor(value), "expected exact non-negative integer")
    if value == 0 then return "0" end
    local chars = {}
    while value > 0 do
        local index = value % 62 + 1
        chars[#chars+1] = ALPHABET:sub(index,index)
        value = math.floor(value/62)
    end
    local result = {}
    for i=#chars,1,-1 do result[#result+1] = chars[i] end
    return table.concat(result)
end
function _M.decode_base62(code)
    assert(type(code) == "string", "code must be a string")
    local value = 0
    for character in code:gmatch(".") do
        local index = ALPHABET:find(character,1,true)
        if not index then return nil,"invalid Base62 character" end
        if value > math.floor((9007199254740991-(index-1))/62) then return nil,"Base62 overflow" end
        value = value*62+index-1
    end
    return value
end
function _M.generate(id) return _M.encode_base62(_M.obfuscate(id)) end
function _M.reverse(code)
    local value,err = _M.decode_base62(code)
    if not value then return nil,err end
    value = value-OFFSET
    if value < 0 or value >= MODULUS then return nil,"code is outside the 32-bit space" end
    return multiply32(value,INVERSE)
end
return _M
