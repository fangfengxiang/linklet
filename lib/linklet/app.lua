-- Application composition and OpenResty entry points.
local Database = require("linklet.db.postgres")
local Runtime = require("linklet.repository.runtime")
local Cache = require("linklet.cache.local")
local Request = require("linklet.http.request")
local Response = require("linklet.http.response")
local LinkRepository = require("linklet.repository.short_link")

local _M = {}
local deps, router, gateway_handler

local function configure_admin(config)
    require("linklet.crypto").configure(config.encryption_key or os.getenv("LINKLET_ENCRYPTION_KEY"))
    local group = require("linklet.repository.group").new(deps.db)
    local domain = require("linklet.repository.domain_entry").new(deps.db)
    local tenant = require("linklet.repository.tenant").new(deps.db)
    local credential = require("linklet.repository.credential").new(deps.db)
    local group_config = require("linklet.repository.group_config").new(deps.db)
    local group_core = require("linklet.core.group").new(group)
    local generator = require("linklet.id.generator").new({
        allocator = deps.runtime, segment_size = config.segment_size,
    })

    deps.group_model, deps.domain_entry_model = group, domain
    deps.tenant_model, deps.credential_model = tenant, credential
    deps.group_config_model, deps.group_core, deps.id_generator = group_config, group_core, generator
    deps.auth = require("linklet.admin.auth").new(credential)
    deps.json = require("linklet.http.json").new()
    deps.validate = require("linklet.http.validate").new_with_rules({
        target_url = {required = true, type = "string", max_len = 2048},
        group_id = {required = true, type = "number"},
        code = {required = false, type = "string", max_len = 20},
    })
    deps.disable_validate = require("linklet.http.validate").new_with_rules({
        code = {required = true, type = "string", max_len = 20},
    })
    deps.shorten_handler = require("linklet.admin.handlers.short_link").new({
        id_generator = generator,
        obfuscator = require("linklet.id.obfuscator"),
        link_model = deps.link_model,
        short_link_repository = require("linklet.repository.slds").new(deps.link_model),
        group_model = group,
        tenant_model = tenant,
        cache = deps.cache,
    })
    deps.tenant_handler = require("linklet.admin.handlers.tenant").new({tenant_model = tenant})
    deps.credential_handler = require("linklet.admin.handlers.credential").new({
        credential_model = credential, tenant_model = tenant,
    })
    deps.resources_handler = require("linklet.admin.handlers.resources").new({
        domain_entry_model = domain, group_model = group, group_core = group_core,
        group_config_model = group_config, tenant_model = tenant,
    })
    router = require("linklet.admin.routes").create(deps)
end

function _M.init(config)
    config = config or {}
    local role = config.role or "combined"
    assert(role == "combined" or role == "admin" or role == "gateway", "invalid application role")
    local db = Database.new(config.database or {
        database = "linklet", user = "linklet", password = "", host = "127.0.0.1", port = 5432,
    })
    local runtime = Runtime.new(db)
    local cache = Cache.new(config.cache_dict or "linklet_cache")
    deps = {
        role = role, db = db, runtime = runtime, cache = cache,
        link_model = LinkRepository.new(db),
        cache_sync = require("linklet.cache.sync").new(runtime, cache, config.cache_sync_interval or 0.5),
    }
    router, gateway_handler = nil, nil
    if role ~= "gateway" then configure_admin(config) end
    if role ~= "admin" then
        local resolver = require("linklet.gateway.resolver").new({
            resolution_repository = deps.link_model,
            cache = cache, cache_ttl = config.cache_ttl or 300,
            now = ngx and ngx.now or os.time,
            lifecycle = require("linklet.core.short_link_policy").lifecycle,
        })
        deps.resolver = resolver
        gateway_handler = require("linklet.gateway.handler").new(resolver)
    end
    return deps
end

function _M.init_worker()
    assert(deps.cache_sync:start())
end

function _M.health()
    local ready = deps.runtime:health()
    if not ready then ngx.status = 503; ngx.say("unavailable"); return end
    ngx.say("ok")
end

local function context(with_request)
    local ctx = {method = "GET", uri = "/", response = Response.new(), params = {}}
    if ngx then
        ctx.method, ctx.uri, ctx.host = ngx.req.get_method(), ngx.var.uri, ngx.var.host
        if with_request then ctx.request = Request.new(ngx) end
    else
        ctx.method = os.getenv("REQUEST_METHOD") or "GET"
        ctx.uri = os.getenv("REQUEST_URI") or "/"
    end
    return ctx
end

local function execute(handler, method, ctx)
    local ok, result = pcall(handler[method], handler, ctx)
    if not ok then
        if not ctx.response.sent and not (ngx and ngx.headers_sent) then
            return ctx.response:internal_error("internal server error")
        end
        return
    end
    if not result and not ctx.response.sent and not (ngx and ngx.headers_sent) then
        if ctx.auth_error then return ctx.response:unauthorized(ctx.auth_error) end
        return ctx.response:internal_error("unknown error")
    end
    return result
end

function _M.handle_admin()
    if not deps then _M.init() end
    local ctx = context(true)
    if not router then return ctx.response:not_found("admin API is not enabled") end
    return execute(router, "dispatch", ctx)
end

function _M.handle_gateway()
    if not deps then _M.init() end
    local ctx = context(false)
    if not gateway_handler then return ctx.response:not_found("gateway is not enabled") end
    return execute(gateway_handler, "handle", ctx)
end

-- Compatibility entry for hosts migrating to the explicit entry points.
function _M.handle_request()
    local uri = ngx and ngx.var.uri or os.getenv("REQUEST_URI") or "/"
    if uri:sub(1, 8) == "/api/v1/" then return _M.handle_admin() end
    return _M.handle_gateway()
end

function _M.get_deps() return deps end
function _M.get_router() return router end
return _M
