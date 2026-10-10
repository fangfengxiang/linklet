package = "linklet"
version = "scm-1"
source = {
    url = "git://github.com/frank/linklet.git",
    branch = "main",
}
description = {
    summary = "A multi-tenant short link system built on OpenResty + Lua + PostgreSQL",
    detailed = [[
Linklet is a self-hosted short link service that provides:
- Short code generation (golden ratio obfuscation + Base62)
- Segment-based ID allocation from PostgreSQL
- Cache-first resolution gateway (ngx.shared.DICT)
- Management API with AK/SK HMAC authentication
- Multi-tenant isolation through relationship chain
    ]],
    homepage = "https://github.com/frank/linklet",
    license = "MIT",
}
dependencies = {
    "lua >= 5.1",
    "pgmoon >= 1.12.0",
    "lua-cjson >= 2.1.0",
}
build_dependencies = {
    "busted >= 2.0.0",
    "luacov >= 0.13.0",
    "luacheck >= 1.0.0",
}
test_dependencies = {
    "busted >= 2.0.0",
    "luacov >= 0.13.0",
}
build = {
    type = "builtin",
    modules = {
        ["linklet.app"] = "src/app.lua",
        ["linklet.router"] = "src/router.lua",
        ["linklet.routes"] = "src/routes.lua",
        ["linklet.lib.database"] = "src/lib/database.lua",
        ["linklet.lib.cache"] = "src/lib/cache.lua",
        ["linklet.lib.request"] = "src/lib/request.lua",
        ["linklet.lib.response"] = "src/lib/response.lua",
        ["linklet.lib.obfuscator"] = "src/lib/obfuscator.lua",
        ["linklet.lib.id_generator"] = "src/lib/id_generator.lua",
        ["linklet.middleware.json"] = "src/middleware/json.lua",
        ["linklet.middleware.validate"] = "src/middleware/validate.lua",
        ["linklet.middleware.auth"] = "src/middleware/auth.lua",
        ["linklet.shorten.handler"] = "src/shorten/handler.lua",
        ["linklet.shorten.cache_handler"] = "src/shorten/cache_handler.lua",
        ["linklet.shorten.resolve_handler"] = "src/shorten/resolve_handler.lua",
        ["linklet.shorten.redirect_handler"] = "src/shorten/redirect_handler.lua",
        ["linklet.models.base_model"] = "src/models/base_model.lua",
        ["linklet.models.link"] = "src/models/link.lua",
        ["linklet.models.tenant"] = "src/models/tenant.lua",
        ["linklet.models.tenant_credential"] = "src/models/tenant_credential.lua",
        ["linklet.models.scene"] = "src/models/scene.lua",
        ["linklet.models.domain_entry"] = "src/models/domain_entry.lua",
    },
}
test = {
    type = "command",
    script = "busted spec/",
}
