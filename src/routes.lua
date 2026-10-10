-- src/routes.lua
-- 路由定义 / Route definitions
-- 短链业务 API: /api/v1/shorten/*
-- 后台管理 API: /api/v1/admin/*  (nginx 层 IP 白名单限制)
-- 短码解析网关: /:code

local Router = require("router")
local _M = {}

--- 创建路由器并注册路由 / Create router with all routes registered
-- @param deps 依赖注入表
--   - auth: 认证中间件
--   - validate: 校验中间件
--   - json: JSON 中间件
--   - shorten_handler: 短链管理处理器
--   - cache_handler: 缓存处理器
--   - resolve_handler: 解析处理器
--   - redirect_handler: 重定向处理器
function _M.create(deps)
    local router = Router.new()

    -- 解析网关路由 / Resolution gateway routes
    -- GET /:code → cache → resolve → redirect
    router:get("/:code", deps.cache_handler, deps.resolve_handler, deps.redirect_handler)

    -- 短链业务 API / Short link business API
    -- 创建短链 / Create short link
    router:post("/api/v1/shorten/create",
        deps.auth,
        deps.json,
        deps.validate,
        function(ctx)
            return deps.shorten_handler:create(ctx)
        end
    )

    -- 生成短链（含 URL）/ Generate short link with full URL
    router:post("/api/v1/shorten/gen",
        deps.auth,
        deps.json,
        deps.validate,
        function(ctx)
            return deps.shorten_handler:gen(ctx)
        end
    )

    -- 停用短链 / Disable short link
    router:put("/api/v1/shorten/disable",
        deps.auth,
        deps.json,
        deps.validate,
        function(ctx)
            return deps.shorten_handler:disable(ctx)
        end
    )

    -- 后台管理 API / Admin management API
    -- nginx 层已限制 IP 白名单，此处不再加 auth 中间件
    -- 租户管理 / Tenant management
    router:post("/api/v1/admin/tenant/create",
        deps.json,
        function(ctx)
            return deps.tenant_handler:create(ctx)
        end
    )

    router:get("/api/v1/admin/tenant/list",
        function(ctx)
            return deps.tenant_handler:list(ctx)
        end
    )

    -- 凭证管理 / Credential management
    router:post("/api/v1/admin/credential/create",
        deps.json,
        function(ctx)
            return deps.credential_handler:create(ctx)
        end
    )

    router:put("/api/v1/admin/credential/disable",
        deps.json,
        function(ctx)
            return deps.credential_handler:disable(ctx)
        end
    )

    return router
end

return _M
