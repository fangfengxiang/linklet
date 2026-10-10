-- spec/router_spec.lua
-- 路由器测试：路由匹配、中间件链
-- Router tests: route matching, middleware chain

local Router = require("router")

describe("Router", function()
    describe("route matching", function()
        it("matches exact path", function()
            local r = Router.new()
            local called = false
            r:get("/health", function(ctx) called = true end)

            local route, params = r:match("GET", "/health")
            assert.truthy(route)
            assert.same({}, params)
        end)

        it("matches path with parameter", function()
            local r = Router.new()
            r:get("/:code", function(ctx) end)

            local route, params = r:match("GET", "/aB9xK2")
            assert.truthy(route)
            assert.equals("aB9xK2", params.code)
        end)

        it("returns nil for unmatched route", function()
            local r = Router.new()
            r:get("/health", function(ctx) end)

            local route = r:match("GET", "/nonexistent")
            assert.is_nil(route)
        end)

        it("distinguishes HTTP methods", function()
            local r = Router.new()
            r:get("/items", function(ctx) end)
            r:post("/items", function(ctx) end)

            local get_route = r:match("GET", "/items")
            local post_route = r:match("POST", "/items")
            assert.truthy(get_route)
            assert.truthy(post_route)
            assert.not_equals(get_route, post_route)
        end)

        it("matches multi-segment paths", function()
            local r = Router.new()
            r:get("/admin/links/:code", function(ctx) end)

            local route, params = r:match("GET", "/admin/links/aB9xK2")
            assert.truthy(route)
            assert.equals("aB9xK2", params.code)
        end)
    end)

    describe("middleware chain", function()
        it("executes middleware in order", function()
            local r = Router.new()
            local order = {}

            local mw1 = {handle = function(self, ctx, next)
                order[#order + 1] = "mw1-before"
                local result = next()
                order[#order + 1] = "mw1-after"
                return result
            end}

            local mw2 = {handle = function(self, ctx, next)
                order[#order + 1] = "mw2-before"
                local result = next()
                order[#order + 1] = "mw2-after"
                return result
            end}

            r:get("/test", mw1, mw2, function(ctx)
                order[#order + 1] = "handler"
            end)

            local ctx = {method = "GET", uri = "/test", response = {not_found = function() end}}
            r:dispatch(ctx)

            assert.same({"mw1-before", "mw2-before", "handler", "mw2-after", "mw1-after"}, order)
        end)

        it("middleware can short-circuit the chain", function()
            local r = Router.new()
            local handler_called = false

            local auth_mw = {handle = function(self, ctx, next)
                ctx.auth_error = "forbidden"
                return nil, "forbidden"
            end}

            r:get("/protected", auth_mw, function(ctx)
                handler_called = true
            end)

            local ctx = {method = "GET", uri = "/protected", response = {}}
            local result, err = r:dispatch(ctx)

            assert.is_false(handler_called)
            assert.equals("forbidden", err)
        end)

        it("global middleware runs before route middleware", function()
            local r = Router.new()
            local order = {}

            local global_mw = {handle = function(self, ctx, next)
                order[#order + 1] = "global"
                return next()
            end}

            local route_mw = {handle = function(self, ctx, next)
                order[#order + 1] = "route"
                return next()
            end}

            r:use(global_mw)
            r:get("/test", route_mw, function(ctx)
                order[#order + 1] = "handler"
            end)

            local ctx = {method = "GET", uri = "/test", response = {}}
            r:dispatch(ctx)

            assert.same({"global", "route", "handler"}, order)
        end)
    end)

    describe("dispatch", function()
        it("returns not found for unmatched route", function()
            local r = Router.new()
            local not_found_called = false

            local ctx = {
                method = "GET",
                uri = "/nonexistent",
                response = {not_found = function(self, msg) not_found_called = true end}
            }

            r:dispatch(ctx)
            assert.truthy(not_found_called)
        end)

        it("passes matched params to handler", function()
            local r = Router.new()
            local received_params

            r:get("/:code", function(ctx)
                received_params = ctx.params
            end)

            local ctx = {
                method = "GET",
                uri = "/aB9xK2",
                response = {},
                request = {all_params = function() return {} end}
            }

            r:dispatch(ctx)
            assert.equals("aB9xK2", received_params.code)
        end)
    end)
end)
