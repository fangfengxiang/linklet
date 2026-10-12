-- src/shorten/handler.lua
-- 短链管理处理器：create, gen, disable
-- Short link management handler: create, gen, disable

local setmetatable = setmetatable
local tostring = tostring
local type = type

local _M = {}
_M.__index = _M

--- 创建管理处理器 / Create management handler
-- @param deps 依赖注入表
--   - id_generator: 发号器实例
--   - obfuscator: 短码生成器
--   - link_model: 短链模型
--   - scene_model: 场景模型
--   - cache: 缓存实例
--   - response: 响应工具
function _M.new(deps)
    local self = setmetatable({}, _M)
    self.id_generator = deps.id_generator
    self.obfuscator = deps.obfuscator
    self.link_model = deps.link_model
    self.scene_model = deps.scene_model
    self.cache = deps.cache
    return self
end

--- 创建短链 / Create short link
-- POST /api/v1/shorten/create
-- @param ctx 请求上下文
-- @return true or nil, err
function _M:create(ctx)
    local params = ctx.params or ctx.request:all_params()
    local target_url = params.target_url
    local scene_id = tonumber(params.scene_id)

    -- 参数校验
    if not target_url or target_url == "" then
        return ctx.response:error_response(4001, "target_url is required", 400)
    end
    if not scene_id then
        return ctx.response:error_response(4002, "scene_id is required", 400)
    end

    -- 校验场景归属 / Validate scene ownership
    local scene, scene_err = self.scene_model:find_by_id_with_domain(scene_id)
    if not scene then
        if scene_err then return ctx.response:internal_error("database unavailable") end
        return ctx.response:error_response(4003, "scene not found or inactive", 404)
    end
    if scene.tenant_id ~= ctx.tenant_id then
        return ctx.response:error_response(4004, "scene does not belong to tenant", 403)
    end

    -- 获取 ID / Get next ID
    local id, err = self.id_generator:next_id()
    if not id then
        return ctx.response:internal_error("failed to generate ID: " .. tostring(err))
    end

    -- 生成短码 / Generate short code
    local code = self.obfuscator.generate(id)

    -- 创建短链记录 / Create link record
    local link, lerr = self.link_model:create({
        code = code,
        target_url = target_url,
        scene_id = scene_id,
        expires_at = params.expires_at,
    })
    if not link then
        return ctx.response:internal_error("failed to create link: " .. tostring(lerr))
    end

    -- 返回结果 / Return result
    return ctx.response:success({
        code = code,
    })
end

--- 生成短链（含完整 URL）/ Generate short link with full URL
-- POST /api/v1/shorten/gen
-- @param ctx 请求上下文
-- @return true or nil, err
function _M:gen(ctx)
    -- 先执行创建逻辑
    local params = ctx.params or ctx.request:all_params()
    local target_url = params.target_url
    local scene_id = tonumber(params.scene_id)

    if not target_url or target_url == "" then
        return ctx.response:error_response(4001, "target_url is required", 400)
    end
    if not scene_id then
        return ctx.response:error_response(4002, "scene_id is required", 400)
    end

    -- 查找场景及域名 / Find scene with domain
    local scene, scene_err = self.scene_model:find_by_id_with_domain(scene_id)
    if not scene then
        if scene_err then return ctx.response:internal_error("database unavailable") end
        return ctx.response:error_response(4003, "scene not found or inactive", 404)
    end
    if scene.tenant_id ~= ctx.tenant_id then
        return ctx.response:error_response(4004, "scene does not belong to tenant", 403)
    end
    if not scene.domain or scene.domain == "" or tonumber(scene.domain_status) ~= 1 then
        return ctx.response:error_response(4005, "domain not configured for scene", 400)
    end

    -- 获取 ID / Get next ID
    local id, err = self.id_generator:next_id()
    if not id then
        return ctx.response:internal_error("failed to generate ID: " .. tostring(err))
    end

    -- 生成短码
    local code = self.obfuscator.generate(id)

    -- 创建短链记录
    local link, lerr = self.link_model:create({
        code = code,
        target_url = target_url,
        scene_id = scene_id,
        expires_at = params.expires_at,
    })
    if not link then
        return ctx.response:internal_error("failed to create link: " .. tostring(lerr))
    end

    -- 拼接完整短链 URL
    local domain = scene.domain:gsub("/+$", "")
    if not domain:match("^https?://") then domain = "https://" .. domain end
    local short_url = domain .. "/" .. code

    return ctx.response:success({
        code = code,
        short_url = short_url,
    })
end

--- 停用短链 / Disable short link
-- PUT /api/v1/shorten/disable
-- @param ctx 请求上下文
-- @return true or nil, err
function _M:disable(ctx)
    local params = ctx.params or ctx.request:all_params()
    local code = params.code

    if not code or code == "" then
        return ctx.response:error_response(4001, "code is required", 400)
    end

    -- 停用短链 / Disable link
    local link, err = self.link_model:disable(code, ctx.tenant_id)
    if not link then
        if err then return ctx.response:internal_error("database unavailable") end
        return ctx.response:error_response(4006, "link not found or already disabled", 404)
    end

    -- 失效缓存 / Invalidate cache
    if self.cache then
        self.cache:invalidate(code)
    end

    return ctx.response:success({
        code = code,
        status = "disabled",
    })
end

return _M
