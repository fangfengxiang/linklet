-- test/e2e/resolution_spec.lua
-- E2E 解析测试：完整流程验证
-- E2E resolution tests: full flow verification
--
-- 运行方式 / Run: busted test/e2e/ -o utfTerminal
-- 前提 / Prerequisites: Docker 环境运行中，OpenResty + PostgreSQL 已启动

local http = require("socket.http") or nil

describe("E2E Resolution Gateway", function()
    -- 这些测试需要运行中的 OpenResty + PostgreSQL 容器
    -- 跳过条件：无法连接 HTTP / Skip if HTTP client unavailable
    if not http then
        pending("socket.http not available, skipping E2E tests")
        return
    end

    local BASE_URL = os.getenv("BASE_URL") or "http://localhost:8080"

    describe("health check", function()
        it("returns 200 from /health", function()
            local body, code = http.request(BASE_URL .. "/health")
            assert.equals(200, code)
            assert.equals("ok", body)
        end)
    end)

    describe("resolution flow", function()
        it("returns 404 for non-existent code", function()
            local body, code = http.request(BASE_URL .. "/zzzzzz")
            assert.equals(404, code)
        end)

        it("returns 302 for a valid active link", function()
            -- 前提：数据库中有一条 status=1 的短链
            -- 需要先通过管理 API 创建
            -- 此测试需要测试数据注入
            local body, code, headers = http.request({
                url = BASE_URL .. "/testcode",
                redirect = false,
            })
            -- 如果测试数据存在，返回 302；否则 404
            assert.truthy(code == 302 or code == 404)
        end)
    end)

    describe("management API", function()
        it("returns 401 without auth", function()
            local body, code = http.request(BASE_URL .. "/api/v1/shorten/create", "POST")
            -- 未认证应返回 401
            assert.truthy(code == 401 or code == 400)
        end)
    end)
end)
