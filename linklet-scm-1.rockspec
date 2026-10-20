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
- Shared scene authorization through tenant grants
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
        ["linklet.core.domain_entry"] = "lib/linklet/core/domain_entry.lua",
        ["linklet.admin.auth"] = "lib/linklet/admin/auth.lua",
        ["linklet.admin.handlers.credential"] = "lib/linklet/admin/handlers/credential.lua",
        ["linklet.admin.handlers.resources"] = "lib/linklet/admin/handlers/resources.lua",
        ["linklet.admin.handlers.short_link"] = "lib/linklet/admin/handlers/short_link.lua",
        ["linklet.admin.handlers.tenant"] = "lib/linklet/admin/handlers/tenant.lua",
        ["linklet.admin.routes"] = "lib/linklet/admin/routes.lua",
        ["linklet.app"] = "lib/linklet/app.lua",
        ["linklet.cache.local"] = "lib/linklet/cache/local.lua",
        ["linklet.cache.sync"] = "lib/linklet/cache/sync.lua",
        ["linklet.core.short_link"] = "lib/linklet/core/short_link.lua",
        ["linklet.core.time"] = "lib/linklet/core/time.lua",
        ["linklet.crypto"] = "lib/linklet/crypto.lua",
        ["linklet.db.postgres"] = "lib/linklet/db/postgres.lua",
        ["linklet.gateway.cache"] = "lib/linklet/gateway/cache.lua",
        ["linklet.gateway.host"] = "lib/linklet/gateway/host.lua",
        ["linklet.gateway.redirect"] = "lib/linklet/gateway/redirect.lua",
        ["linklet.gateway.resolver"] = "lib/linklet/gateway/resolver.lua",
        ["linklet.http.json"] = "lib/linklet/http/json.lua",
        ["linklet.http.request"] = "lib/linklet/http/request.lua",
        ["linklet.http.response"] = "lib/linklet/http/response.lua",
        ["linklet.http.router"] = "lib/linklet/http/router.lua",
        ["linklet.http.validate"] = "lib/linklet/http/validate.lua",
        ["linklet.id.generator"] = "lib/linklet/id/generator.lua",
        ["linklet.id.obfuscator"] = "lib/linklet/id/obfuscator.lua",
        ["linklet.repository.base"] = "lib/linklet/repository/base.lua",
        ["linklet.repository.credential"] = "lib/linklet/repository/credential.lua",
        ["linklet.repository.domain_entry"] = "lib/linklet/repository/domain_entry.lua",
        ["linklet.repository.scene"] = "lib/linklet/repository/scene.lua",
        ["linklet.repository.scene_config"] = "lib/linklet/repository/scene_config.lua",
        ["linklet.repository.short_link"] = "lib/linklet/repository/short_link.lua",
        ["linklet.repository.tenant"] = "lib/linklet/repository/tenant.lua",
        ["admin.credential_handler"] = "src/admin/credential_handler.lua",
        ["admin.tenant_handler"] = "src/admin/tenant_handler.lua",
        ["app"] = "src/app.lua",
        ["lib.cache"] = "src/lib/cache.lua",
        ["lib.cache_sync"] = "src/lib/cache_sync.lua",
        ["lib.crypto"] = "src/lib/crypto.lua",
        ["lib.database"] = "src/lib/database.lua",
        ["lib.id_generator"] = "src/lib/id_generator.lua",
        ["lib.obfuscator"] = "src/lib/obfuscator.lua",
        ["lib.request"] = "src/lib/request.lua",
        ["lib.response"] = "src/lib/response.lua",
        ["linklet"] = "src/linklet.lua",
        ["middleware.auth"] = "src/middleware/auth.lua",
        ["middleware.json"] = "src/middleware/json.lua",
        ["middleware.validate"] = "src/middleware/validate.lua",
        ["models.base_model"] = "src/models/base_model.lua",
        ["models.domain_entry"] = "src/models/domain_entry.lua",
        ["models.link"] = "src/models/link.lua",
        ["models.scene"] = "src/models/scene.lua",
        ["models.tenant"] = "src/models/tenant.lua",
        ["models.tenant_credential"] = "src/models/tenant_credential.lua",
        ["router"] = "src/router.lua",
        ["routes"] = "src/routes.lua",
        ["shorten.cache_handler"] = "src/shorten/cache_handler.lua",
        ["shorten.handler"] = "src/shorten/handler.lua",
        ["shorten.redirect_handler"] = "src/shorten/redirect_handler.lua",
        ["shorten.resolve_handler"] = "src/shorten/resolve_handler.lua",
    },
}
test = {
    type = "command",
    script = "busted spec/",
}
