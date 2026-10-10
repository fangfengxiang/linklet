-- src/lib/obfuscator.lua
-- 短码生成算法：黄金比例混淆 + Base62 编码
-- Short code generation: golden ratio obfuscation + Base62 encoding

local string = string
local math = math
local tonumber = tonumber

local _M = {}

-- 黄金比例常数（32位） / Golden ratio constant (32-bit)
-- (√5 - 1) / 2 × 2^32 ≈ 2654435769 = 0x9E3779B9
-- 使用奇数保证与 2^32 互质，模 2^32 乘法严格双射
local GOLDEN_RATIO = 2654435769

-- 模数 / Modulus (2^32)
local MODULUS = 4294967296

-- Base62 字符集 / Base62 character set
local BASE62_CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local BASE62 = 62

-- 基础偏移 / Base offset (62^5 = 916132832)
-- 保证 Base62 编码后至少 6 位
local BASE_OFFSET = 916132832

--- 黄金比例混淆 / Golden ratio obfuscation
-- 将连续整数 ID 映射为非连续、不可预测的数值
-- @param id 正整数 ID
-- @return 混淆后的正整数
function _M.obfuscate(id)
    if type(id) ~= "number" or id < 0 then
        error("id must be a non-negative number, got " .. tostring(id), 2)
    end
    -- 模 2^32 乘法：id × golden_ratio mod 2^32
    -- 对于 Lua 5.3+ 整数，% 运算符精确
    -- 对于 Lua 5.1/LuaJIT 双精度浮点，id < 2^22 时精确
    local result = (id * GOLDEN_RATIO) % MODULUS
    -- 加基础偏移保证编码长度 ≥ 6
    return math.floor(result) + BASE_OFFSET
end

--- Base62 编码 / Encode integer to Base62 string
-- @param num 非负整数
-- @return Base62 字符串
function _M.encode_base62(num)
    if type(num) ~= "number" or num < 0 then
        error("num must be a non-negative number, got " .. tostring(num), 2)
    end
    num = math.floor(num)
    if num == 0 then
        return "0"
    end
    local result = {}
    while num > 0 do
        local idx = (num % BASE62) + 1
        result[#result + 1] = string.sub(BASE62_CHARS, idx, idx)
        num = math.floor(num / BASE62)
    end
    -- 反转拼接 / reverse and join
    local s = ""
    for i = #result, 1, -1 do
        s = s .. result[i]
    end
    return s
end

--- Base62 解码 / Decode Base62 string to integer
-- @param s Base62 字符串
-- @return 整数
function _M.decode_base62(s)
    if type(s) ~= "string" then
        error("s must be a string, got " .. type(s), 2)
    end
    local num = 0
    for i = 1, #s do
        local c = string.sub(s, i, i)
        local idx = string.find(BASE62_CHARS, c, 1, true)
        if not idx then
            return nil, "invalid character in Base62 string: " .. c
        end
        num = num * BASE62 + (idx - 1)
    end
    return num
end

--- 生成短码 / Generate short code from ID
-- 两阶段：混淆 → Base62 编码
-- @param id 正整数 ID（来自发号器）
-- @return 短码字符串（≥6 位）
function _M.generate(id)
    return _M.encode_base62(_M.obfuscate(id))
end

--- 从短码反解 ID / Reverse-derive original ID from short code
-- 注意：此函数仅用于调试/验证，不用于生产路径
-- @param code 短码字符串
-- @return 原始 ID 或 nil, err
function _M.reverse(code)
    local num, err = _M.decode_base62(code)
    if not num then
        return nil, err
    end
    -- 减去基础偏移
    num = num - BASE_OFFSET
    if num < 0 then
        return nil, "code is too short (below base offset)"
    end
    -- 逆向乘法：需要找到 x 使得 (x * GOLDEN_RATIO) % MODULUS == num
    -- 黄金比例常数的模逆元 / modular multiplicative inverse
    -- 由于 GOLDEN_RATIO 是奇数，与 2^32 互质，存在模逆元
    -- 使用扩展欧几里得算法求逆元
    -- 对于测试目的，使用暴力搜索在小范围内验证
    -- 生产环境不使用此函数
    local inverse = _M._modular_inverse(GOLDEN_RATIO, MODULUS)
    if not inverse then
        return nil, "failed to compute modular inverse"
    end
    return (num * inverse) % MODULUS
end

--- 扩展欧几里得算法求模逆元 / Extended Euclidean for modular inverse
-- 不导出，仅内部使用
function _M._modular_inverse(a, m)
    -- 使用 Python 风格的大数运算（Lua 双精度浮点）
    -- 对于 32 位范围内的值，使用迭代法
    local old_r, new_r = a, m
    local old_s, new_s = 1, 0
    while new_r ~= 0 do
        local quotient = math.floor(old_r / new_r)
        old_r, new_r = new_r, old_r - quotient * new_r
        old_s, new_s = new_s, old_s - quotient * new_s
    end
    if old_r ~= 1 then
        return nil  -- 不互质，无逆元
    end
    -- 确保 old_s 为正
    old_s = old_s % m
    if old_s < 0 then
        old_s = old_s + m
    end
    return old_s
end

return _M
