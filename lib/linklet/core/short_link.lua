-- Domain use case: no HTTP, ngx or SQL dependencies.
local _M = {}
_M.__index = _M
function _M.new(deps) return setmetatable(deps, _M) end
local function failure(message, status, code) return nil, {message=message,status=status,code=code} end
function _M:create(tenant_id, params)
    local url, scene_id = params.target_url, tonumber(params.scene_id)
    if type(url)~="string" or url=="" then return failure("target_url is required",400,4001) end
    if #url>2048 or not url:match("^https?://[^/%s?#]+") or url:find("[%c%s]") then
        return failure("target_url must be an HTTP(S) URL",400,4001)
    end
    if not scene_id or scene_id<1 or scene_id>4294967295 or scene_id~=math.floor(scene_id) then
        return failure("scene_id must be a uint32",400,4002)
    end
    if params.expires_at~=nil then
        local epoch = require("linklet.core.time").parse(params.expires_at)
        if not epoch or epoch <= (self.now or os.time)() then
            return failure("expires_at must be a future RFC3339 timestamp",400,4007)
        end
    end
    local scene, err = self.scene_model:find_by_id_with_domain(scene_id)
    if err then return failure("database unavailable",500,500) end
    if not scene or tonumber(scene.status)~=1 then return failure("scene not found or inactive",404,4003) end
    local allowed, aerr = self.tenant_model:authorized(tenant_id, scene_id)
    if aerr then return failure("database unavailable",500,500) end
    if not allowed then return failure("scene not authorized",403,4004) end
    if not scene.domain or scene.domain=="" or tonumber(scene.domain_status)~=2 then
        return failure("domain not configured for scene",400,4005)
    end
    local id, ierr = self.id_generator:next_id()
    if not id then return failure("failed to generate ID: "..tostring(ierr),500,500) end
    local code = self.obfuscator.generate(id)
    local link, lerr = self.link_model:create({code=code,target_url=url,scene_id=scene_id,
        expires_at=params.expires_at}, tenant_id)
    if not link then return failure("failed to create link: "..tostring(lerr),500,500) end
    return {code=code,domain=scene.domain}
end
return _M
