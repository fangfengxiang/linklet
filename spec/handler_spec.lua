-- spec/handler_spec.lua
-- 管理处理器测试：create, gen, disable
-- Management handler tests: create, gen, disable

local helper = require("helper")
local Obfuscator = require("linklet.id.obfuscator")
local ShortenHandler = require("linklet.admin.handlers.short_link")
local IdGenerator = require("linklet.id.generator")

describe("ShortenHandler", function()
    local handler, deps, mock_link_model, mock_scene_model, mock_cache, resp, id_gen

    before_each(function()
        mock_cache = helper.mock_cache()

        -- Mock link model
        mock_link_model = {
            create = function(self, data) return data end,
            disable = function(self, code) return {code = code, status = 2} end,
            find_by_code = function(self, code) return nil end,
        }

        -- Mock scene model
        mock_scene_model = {
            find_by_id_with_domain = function(self, scene_id)
                return {
                    scene_id = scene_id,
                    status = 1,
                    name = "test_scene",
                    domain_entry_id = 1,
                    domain = "s.example.com",
                    domain_status = 2,
                }
            end,
        }

        -- Mock ID generator
        local counter = 0
        id_gen = {
            next_id = function(self)
                counter = counter + 1
                return counter
            end,
        }

        deps = {
            id_generator = id_gen,
            obfuscator = Obfuscator,
            link_model = mock_link_model,
            scene_model = mock_scene_model,
            tenant_model = {authorized=function(_,id) return id==1 end},
            cache = mock_cache,
        }

        handler = ShortenHandler.new(deps)
        resp = helper.mock_response()
    end)

    describe("create", function()
        it("creates a short link with valid params", function()
            local ctx = {
                params = {target_url = "https://example.com/page", scene_id = 1},
                tenant_id = 1,
                response = resp,
            }

            handler:create(ctx)

            assert.equals(200, resp._status)
            assert.equals(0, resp._body.code)
            assert.truthy(resp._body.data.code)
            assert.truthy(#resp._body.data.code >= 6)
        end)

        it("returns 400 when target_url is missing", function()
            local ctx = {
                params = {scene_id = 1},
                tenant_id = 1,
                response = resp,
            }

            handler:create(ctx)

            assert.equals(400, resp._status)
            assert.equals(4001, resp._body.code)
            assert.truthy(resp._body.message:find("target_url"))
        end)

        it("returns 400 when scene_id is missing", function()
            local ctx = {
                params = {target_url = "https://example.com"},
                tenant_id = 1,
                response = resp,
            }

            handler:create(ctx)

            assert.equals(400, resp._status)
            assert.equals(4002, resp._body.code)
        end)

        it("returns 404 when scene not found", function()
            mock_scene_model.find_by_id_with_domain = function() return nil end

            local ctx = {
                params = {target_url = "https://example.com", scene_id = 999},
                tenant_id = 1,
                response = resp,
            }

            handler:create(ctx)

            assert.equals(404, resp._status)
        end)

        it("returns 403 when tenant has no scene grant", function()
            local ctx = {
                params = {target_url = "https://example.com", scene_id = 1},
                tenant_id = 999,  -- different tenant
                response = resp,
            }

            handler:create(ctx)

            assert.equals(403, resp._status)
            assert.equals(4004, resp._body.code)
        end)
    end)

    describe("gen", function()
        it("creates short link and returns full URL", function()
            local ctx = {
                params = {target_url = "https://example.com/page", scene_id = 1},
                tenant_id = 1,
                response = resp,
            }

            handler:gen(ctx)

            assert.equals(200, resp._status)
            assert.truthy(resp._body.data.code)
            assert.truthy(resp._body.data.short_url)
            assert.matches("s.example.com", resp._body.data.short_url)
        end)

        it("returns 400 when domain not configured", function()
            mock_scene_model.find_by_id_with_domain = function()
                return {scene_id = 1, status = 1, domain = nil}
            end

            local ctx = {
                params = {target_url = "https://example.com", scene_id = 1},
                tenant_id = 1,
                response = resp,
            }

            handler:gen(ctx)

            assert.equals(400, resp._status)
            assert.equals(4005, resp._body.code)
        end)
    end)

    describe("disable", function()
        it("disables an active link", function()
            local ctx = {
                params = {code = "aB9xK2"},
                tenant_id = 1,
                response = resp,
            }

            handler:disable(ctx)

            assert.equals(200, resp._status)
            assert.equals("disabled", resp._body.data.status)
        end)

        it("invalidates cache on disable", function()
            mock_cache:set("link:aB9xK2", "https://example.com")

            local ctx = {
                params = {code = "aB9xK2"},
                tenant_id = 1,
                response = resp,
            }

            handler:disable(ctx)

            assert.is_nil(mock_cache:get("link:aB9xK2"))
        end)

        it("returns 404 when link not found or already disabled", function()
            mock_link_model.disable = function() return nil end

            local ctx = {
                params = {code = "notfound"},
                tenant_id = 1,
                response = resp,
            }

            handler:disable(ctx)

            assert.equals(404, resp._status)
        end)

        it("returns 400 when code is missing", function()
            local ctx = {
                params = {},
                tenant_id = 1,
                response = resp,
            }

            handler:disable(ctx)

            assert.equals(400, resp._status)
        end)
    end)
end)
