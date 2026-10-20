local _M = {}
function _M.start(root)
    if jit then jit.off() end
    require("luacov.runner").init({statsfile=root .. "/luacov.stats.out",include={"^lib/linklet/", "^" .. root .. "/lib/linklet/"}})
end
function _M.stop(root)
    local runner = require("luacov.runner")
    local normalized = {}
    for name, data in pairs(runner.data) do
        if name:sub(1,#root+1) == root .. "/" then name = name:sub(#root+2) end
        normalized[name] = data
    end
    runner.data = normalized
    runner.shutdown()
end
return _M
