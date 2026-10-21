-- Merge only after all workers exit; concurrent LuaCov saves can lose data.
package.path = ".test-deps/runtime/share/lua/5.1/?.lua;" .. package.path
local stats = require("luacov.stats")
local output = assert(arg[1], "output file missing")
local merged = stats.load(output) or {}
assert(arg[2], "worker coverage files missing")

for index = 2, #arg do
    local incoming = assert(stats.load(arg[index]), "cannot read " .. arg[index])
    for name, data in pairs(incoming) do
        local combined = merged[name] or {max = 0, max_hits = 0}
        combined.max = math.max(combined.max, data.max)
        for line = 1, data.max do
            combined[line] = (combined[line] or 0) + (data[line] or 0)
            combined.max_hits = math.max(combined.max_hits, combined[line])
        end
        merged[name] = combined
    end
end
stats.save(output, merged)
print("Merged " .. (#arg - 1) .. " worker coverage files")
