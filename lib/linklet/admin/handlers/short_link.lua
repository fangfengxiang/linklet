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
--   - group_model: 分组模型
--   - cache: 缓存实例
--   - response: 响应工具
function _M.new(deps)
    local self = setmetatable({}, _M)
    self.id_generator = deps.id_generator
    self.obfuscator = deps.obfuscator
    self.link_model = deps.link_model
    self.group_model = deps.group_model
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
    if not result then return require("linklet.admin.errors").respond(ctx.response,err) end
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
    local data, err = self.use_case:disable(ctx.tenant_id, params.code)
    if not data then return require("linklet.admin.errors").respond(ctx.response, err) end
    if self.cache then self.cache:invalidate(data.code) end
    return ctx.response:success(data)
end

function _M:get(ctx)
    local p = ctx.request:all_params()
    local row, err = self.use_case:get(ctx.tenant_id, p.code)
    if not row then return require("linklet.admin.errors").respond(ctx.response, err) end
    return ctx.response:success(row)
end

return _M
