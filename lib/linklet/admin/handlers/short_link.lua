-- lib/linklet/admin/handlers/short_link.lua
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
    self.use_case = require("linklet.core.short_link").new(deps)
    return self
end

--- 创建短链 / Create short link
-- POST /api/v1/shorten/create
-- @param ctx 请求上下文
-- @return true or nil, err
local function create(self, ctx, full_url)
    local params = ctx.params or ctx.request:all_params()
    local result, err = self.use_case:create(ctx.tenant_id, params)
    if not result then return ctx.response:error_response(err.code,err.message,err.status) end
    local data = {code=result.code}
    if full_url then data.short_url = "https://" .. result.domain .. "/" .. result.code end
    return ctx.response:success(data)
end
function _M:create(ctx) return create(self,ctx,false) end
function _M:gen(ctx) return create(self,ctx,true) end

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

function _M:get(ctx)
    local p=ctx.request:all_params()
    if type(p.code)~="string" or #p.code<1 or #p.code>20 then
        return ctx.response:error_response(4001,"code is required",400)
    end
    local row,err=self.link_model:find_authorized(p.code,ctx.tenant_id)
    if err then return ctx.response:internal_error("database unavailable") end
    if not row then return ctx.response:not_found("link not found") end
    return ctx.response:success(row)
end
return _M
