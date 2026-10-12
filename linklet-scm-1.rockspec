rockspec_format = "3.0"
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
    "pgmoon >= 1.18.0",
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
        ["linklet"] = "src/linklet.lua",
        ["lib.crypto"] = "src/lib/crypto.lua",
        ["lib.cache_sync"] = "src/lib/cache_sync.lua",
        ["admin.tenant_handler"] = "src/admin/tenant_handler.lua",
        ["admin.credential_handler"] = "src/admin/credential_handler.lua",
        ["app"] = "src/app.lua",
        ["router"] = "src/router.lua",
        ["routes"] = "src/routes.lua",
        ["lib.database"] = "src/lib/database.lua",
        ["lib.cache"] = "src/lib/cache.lua",
        ["lib.request"] = "src/lib/request.lua",
        ["lib.response"] = "src/lib/response.lua",
        ["lib.obfuscator"] = "src/lib/obfuscator.lua",
        ["lib.id_generator"] = "src/lib/id_generator.lua",
        ["middleware.json"] = "src/middleware/json.lua",
        ["middleware.validate"] = "src/middleware/validate.lua",
        ["middleware.auth"] = "src/middleware/auth.lua",
        ["shorten.handler"] = "src/shorten/handler.lua",
        ["shorten.cache_handler"] = "src/shorten/cache_handler.lua",
        ["shorten.resolve_handler"] = "src/shorten/resolve_handler.lua",
        ["shorten.redirect_handler"] = "src/shorten/redirect_handler.lua",
        ["models.base_model"] = "src/models/base_model.lua",
        ["models.link"] = "src/models/link.lua",
        ["models.tenant"] = "src/models/tenant.lua",
        ["models.tenant_credential"] = "src/models/tenant_credential.lua",
        ["models.scene"] = "src/models/scene.lua",
        ["models.domain_entry"] = "src/models/domain_entry.lua",
    },
}
test = {
    type = "command",
    script = "busted spec/",
}
