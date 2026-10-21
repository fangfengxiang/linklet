-- Local operator API; network allowlist is enforced by the production Nginx locations.
local _M={}
_M.__index=_M
local function integer(v,max)
    if type(v)~="number" and type(v)~="string" then return nil end
    v=tonumber(v)
    if v and v>=1 and v<=(max or 9007199254740991) and v==math.floor(v) then return v end
end
local function text(v,max) return type(v)=="string" and #v>0 and #v<=max end
local function result(ctx,row,err)
    if err then
        if err=="group_domain_locked" then
            return ctx.response:error_response(409,"group with links cannot change domain",409)
        end
        if tostring(err):find("domain is still bound",1,true) or
            tostring(err):find("domain must be deployed",1,true) or
            tostring(err):find("grants must reference",1,true) then
            return ctx.response:error_response(409,"resource constraint rejected the change",409)
        end
        return ctx.response:internal_error("database operation failed")
    end
    if not row then return ctx.response:error_response(409,"resource missing or state conflict",409) end
    return ctx.response:success(row)
end
function _M.new(deps) return setmetatable(deps,_M) end
function _M:handle(ctx,resource,action)
    local p=ctx.request:all_params()
    local function bad() return ctx.response:error_response(4000,"invalid resource parameters",400) end
    if resource=="domain" then
        local repo=self.domain_entry_model
        if action=="list" then return result(ctx,repo:find_all(100)) end
        if action=="create" then
            local host=require("linklet.core.domain_entry").normalize(p.domain)
            if not host or host~=p.domain or #host>255 or not host:find("%.") or
                (p.tag~=nil and not text(p.tag,100)) or
                (p.description~=nil and not text(p.description,4096)) then return bad() end
            return result(ctx,repo:create(host,p.tag,p.description))
        end
        local id=integer(p.id)
        if not id then return bad() end
        if action=="deploy" then return result(ctx,repo:deploy(id)) end
        return result(ctx,repo:disable(id))
    elseif resource=="group" then
        if action=="list" then
            local id=integer(p.tenant_id)
            if not id then return bad() end
            return result(ctx,self.group_model:find_by_tenant(id,100))
        end
        local id=integer(p.group_id,4294967295)
        if not id then return bad() end
        if action=="create" then
            local domain_id=integer(p.domain_entry_id)
            if not text(p.name,255) or not domain_id then return bad() end
            return result(ctx,self.group_model:create(id,p.name,domain_id))
        end
        local domain_id=p.domain_entry_id and integer(p.domain_entry_id)
        local status=p.status and integer(p.status,2)
        if (p.domain_entry_id~=nil and not domain_id) or (p.status~=nil and not status) or
            (not domain_id and not status) then return bad() end
        return result(ctx,self.group_core:configure(id,domain_id,status))
    elseif resource=="group_config" then
        local id=integer(p.group_id,4294967295)
        if not id then return bad() end
        if action=="list" then return result(ctx,self.group_config_model:list(id)) end
        if not text(p.config_key,128) then return bad() end
        if action=="delete" then return result(ctx,self.group_config_model:delete(id,p.config_key)) end
        if type(p.config_value)~="string" or #p.config_value>65536 or
            (p.description~=nil and not text(p.description,255)) then return bad() end
        return result(ctx,self.group_config_model:set(id,p.config_key,p.config_value,p.description))
    elseif resource=="tenant" then
        local id=integer(p.id)
        if not id then return bad() end
        if action=="status" then
            local status=integer(p.status,2)
            if not status then return bad() end
            return result(ctx,self.tenant_model:set_status(id,status))
        end
        if type(p.group_ids)~="table" then return bad() end
        local ids,count={},0
        for k,v in pairs(p.group_ids) do
            if type(k)~="number" or k<1 or k~=math.floor(k) or not integer(v,4294967295) then return bad() end
            ids[k]=integer(v,4294967295);count=count+1
        end
        if count~=#ids or count>10000 then return bad() end
        return result(ctx,self.tenant_model:grant(id,ids))
    end
    return bad()
end
return _M
