-- src/app.lua
-- 应用入口：初始化依赖、分发请求
-- Application entry point: dependency init, request dispatch

local pcall = pcall
local tostring = tostring
local setmetatable = setmetatable

-- 库导入 / Library imports
local Database = require("lib.database")
local Cache = require("lib.cache")
local Request = require("lib.request")
local Response = require("lib.response")
local Obfuscator = require("lib.obfuscator")
local IdGenerator = require("lib.id_generator")

local Router = require("router")
local Routes = require("routes")

local JsonMiddleware = require("middleware.json")
local ValidateMiddleware = require("middleware.validate")
local AuthMiddleware = require("middleware.auth")

local LinkModel = require("models.link")
local SceneModel = require("models.scene")
local DomainEntryModel = require("models.domain_entry")
local TenantModel = require("models.tenant")
local TenantCredential = require("models.tenant_credential")

local ShortenHandler = require("shorten.handler")
local CacheHandler = require("shorten.cache_handler")
local ResolveHandler = require("shorten.resolve_handler")
local RedirectHandler = require("shorten.redirect_handler")

local TenantHandler = require("admin.tenant_handler")
local CredentialHandler = require("admin.credential_handler")

local _M = {}

-- 全局依赖实例（进程级单例）/ Global dependency instances (process-level singletons)
local deps = nil
local router = nil

--- 初始化依赖 / Initialize dependencies
-- 在 OpenResty init_by_lua 阶段调用
-- @param config 配置表
function _M.init(config)
    config = config or {}

    -- 数据库 / Database
    local db = Database.new(config.database or {
        database = "linklet",
        user = "linklet",
        password = "",
        host = "127.0.0.1",
        port = 5432,
    })

    -- 缓存 / Cache
    local cache = Cache.new(config.cache_dict or "linklet_cache")

    -- 发号器 / ID Generator
    local id_generator = IdGenerator.new({
        db = db,
        segment_size = config.segment_size or 1000,
    })

    -- 模型 / Models
    local link_model = LinkModel.new(db)
    local scene_model = SceneModel.new(db)
    local domain_entry_model = DomainEntryModel.new(db)
    local tenant_model = TenantModel.new(db)
    local credential_model = TenantCredential.new(db)

    -- 中间件 / Middleware
    local json_mw = JsonMiddleware.new()
    local validate_mw = ValidateMiddleware.new_with_rules({
        target_url = {required = true, type = "string", max_len = 2048},
        scene_id = {required = true, type = "number"},
        code = {required = false, type = "string", max_len = 20},
    })
    local auth_mw = AuthMiddleware.new(credential_model)

    -- 处理器 / Handlers
    local shorten_handler = ShortenHandler.new({
        id_generator = id_generator,
        obfuscator = Obfuscator,
        link_model = link_model,
        scene_model = scene_model,
        cache = cache,
    })
    local cache_handler = CacheHandler.new(cache)
    local resolve_handler = ResolveHandler.new({
        link_model = link_model,
        cache = cache,
        cache_ttl = config.cache_ttl or 300,
    })
    local redirect_handler = RedirectHandler.new()

    -- Admin 处理器 / Admin handlers
    local tenant_handler = TenantHandler.new({
        tenant_model = tenant_model,
    })
    local credential_handler = CredentialHandler.new({
        credential_model = credential_model,
        tenant_model = tenant_model,
    })

    deps = {
        db = db,
        cache = cache,
        id_generator = id_generator,
        link_model = link_model,
        scene_model = scene_model,
        domain_entry_model = domain_entry_model,
        tenant_model = tenant_model,
        credential_model = credential_model,
        -- 路由用简短名称 / Short names for routes
        auth = auth_mw,
        json = json_mw,
        validate = validate_mw,
        shorten_handler = shorten_handler,
        cache_handler = cache_handler,
        resolve_handler = resolve_handler,
        redirect_handler = redirect_handler,
        tenant_handler = tenant_handler,
        credential_handler = credential_handler,
    }

    -- 创建路由器 / Create router with routes
    router = Routes.create(deps)

    return deps
end

--- 处理请求 / Handle request
-- 在 OpenResty content_by_lua 阶段调用
function _M.handle_request()
    if not router then
        _M.init()
    end

    local ngx_ok, ngx = pcall(require, "ngx")

    -- 每请求新建 Response 实例 / New Response per request
    local response = Response.new()

    -- 构建请求上下文 / Build request context
    local ctx = {
        method = "GET",
        uri = "/",
        request = nil,
        response = response,
        params = {},
    }

    if ngx_ok then
        ctx.method = ngx.req.get_method()
        ctx.uri = ngx.var.uri
        ctx.request = Request.new(ngx)
    else
        -- 测试模式 / Test mode
        ctx.method = os.getenv("REQUEST_METHOD") or "GET"
        ctx.uri = os.getenv("REQUEST_URI") or "/"
    end

    -- 分发请求 / Dispatch
    local ok_dispatch, result = pcall(router.dispatch, router, ctx)
    if not ok_dispatch then
        -- dispatch 本身抛异常 / dispatch threw error
        if ngx_ok and not ngx.headers_sent then
            ngx.status = 500
            ngx.header["Content-Type"] = "application/json; charset=utf-8"
            ngx.say('{"code":500,"message":"internal server error","data":null}')
        end
        return
    end

    -- 中间件链返回 nil, err 时 / Middleware chain returned error
    -- 如果响应已发送（如 not_found/error_response），不再重复发送
    if not result and ngx_ok and not ngx.headers_sent then
        if ctx.auth_error then
            -- 认证失败 / Auth failed
            ngx.status = 401
            ngx.header["Content-Type"] = "application/json; charset=utf-8"
            ngx.say('{"code":401,"message":"' .. ctx.auth_error .. '","data":null}')
        else
            -- 未发送任何响应 / No response was sent
            ngx.status = 500
            ngx.header["Content-Type"] = "application/json; charset=utf-8"
            ngx.say('{"code":500,"message":"unknown error","data":null}')
        end
    end
end

--- 获取依赖（用于测试）/ Get dependencies (for testing)
function _M.get_deps()
    return deps
end

--- 获取路由器（用于测试）/ Get router (for testing)
function _M.get_router()
    return router
end

return _M
