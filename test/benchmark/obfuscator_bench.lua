-- test/benchmark/obfuscator_bench.lua
-- 短码生成基准测试 / Short code generation benchmark

local Obfuscator = require("linklet.id.obfuscator")

local function bench(name, fn, iterations)
    iterations = iterations or 1000000
    local start = os.clock()
    local sink
    for _ = 1, iterations do
        sink = fn()
    end
    local elapsed = os.clock() - start
    local ops_per_sec = iterations / elapsed
    local us_per_op = (elapsed * 1e6) / iterations
    print(string.format("%-40s %10d ops/s  %8.2f us/op  (%d iterations in %.3fs)",
        name, math.floor(ops_per_sec), us_per_op, iterations, elapsed))
    assert(sink ~= nil)
end

-- 预热 / Warmup
for i = 1, 1000 do
    Obfuscator.generate(i)
end

print("========================================")
print("  Linklet Obfuscator Benchmark")
print("========================================")
print("")

local id = 1
bench("obfuscate()", function()
    local value = Obfuscator.obfuscate(id)
    id = id + 1
    return value
end)

id = 1
bench("encode_base62()", function()
    local value = Obfuscator.encode_base62(Obfuscator.obfuscate(id))
    id = id + 1
    return value
end)

id = 1
bench("generate() (full pipeline)", function()
    local value = Obfuscator.generate(id)
    id = id + 1
    return value
end)

-- 碰撞测试 / Collision test
print("")
print("--- Collision test (1-1000000) ---")
local start = os.clock()
local seen = {}
local collisions = 0
for i = 1, 1000000 do
    local code = Obfuscator.generate(i)
    if seen[code] then
        collisions = collisions + 1
    end
    seen[code] = true
end
local elapsed = os.clock() - start
assert(collisions == 0, "short code collisions detected")
print(string.format("Range: 1-1000000, Collisions: %d, Time: %.3fs", collisions, elapsed))

print("")
print("========================================")
print("  Benchmark complete")
print("========================================")
