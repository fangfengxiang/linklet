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
- Shared group authorization through tenant grants
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
        ["linklet.core.group"] = "lib/linklet/core/group.lua",
        ["linklet.admin.errors"] = "lib/linklet/admin/errors.lua",
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
        ["linklet.repository.group"] = "lib/linklet/repository/group.lua",
        ["linklet.repository.group_config"] = "lib/linklet/repository/group_config.lua",
        ["linklet.repository.short_link"] = "lib/linklet/repository/short_link.lua",
        ["linklet.repository.tenant"] = "lib/linklet/repository/tenant.lua",
    },
}
test = {
    type = "command",
    script = "busted spec/",
}
