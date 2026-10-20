local Time=require("linklet.core.time")
local Core=require("linklet.core.short_link")
local Generator=require("linklet.id.generator")
local Host=require("linklet.gateway.host")
describe("v0.2 domain contracts",function()
    it("parses RFC3339 independent of local timezone and rejects invalid dates",function()
        assert.equals(0,Time.parse("1970-01-01T00:00:00Z"))
        assert.equals(0,Time.parse("1970-01-01T08:00:00+08:00"))
        assert.equals(0.5,Time.parse("1970-01-01T00:00:00.5Z"))
        for _,v in ipairs({false,{},"2025-02-29T00:00:00Z","2024-13-01T00:00:00Z",
            "2024-01-01T24:00:00Z","2024-01-01T00:00:60Z","2024-01-01T00:00:00+24:00",
            "2024-01-01T00:00:00+01:99","bad"}) do assert.is_nil(Time.parse(v)) end
        assert.is_number(Time.parse("2024-02-29T00:00:00-01:00"))
    end)
    it("normalizes host and isolates cache namespaces",function()
        assert.equals("s.example.com",Host.normalize("S.Example.com.:443"))
        assert.not_equals(Host.key("a.example.com","x"),Host.key("b.example.com","x"))
        for _,v in ipairs({false,{},"",".","a..com","a/b","a:bad","-a.com","a-.com",
            ".a.com",string.rep("a",64)..".com"}) do assert.is_nil(Host.normalize(v)) end
        assert.is_nil(Host.key(nil,"x"))
    end)
    it("rejects zero TTL and polling intervals that would violate cache deadlines",function()
        assert.has_error(function() require("linklet.gateway.resolver").new({cache_ttl=0}) end)
        assert.has_error(function() require("linklet.cache.sync").new({}, {}, 0) end)
    end)
    local core, calls
    before_each(function()
        calls=0
        core=Core.new({now=function() return 100 end,
            scene_model={find_by_id_with_domain=function()
                return {status=1,domain_status=2,domain="s.example.com"} end},
            tenant_model={authorized=function(_,id) return id==1 or id==2 end},
            id_generator={next_id=function() return 10 end},obfuscator={generate=function() return "code10" end},
            link_model={create=function(_,data) calls=calls+1;return data end}})
    end)
    it("allows both granted tenants to create in a shared scene",function()
        for _,id in ipairs({1,2}) do
            assert.equals("code10",assert(core:create(id,{scene_id=7,target_url="https://example.com"})).code)
        end
        assert.equals(2,calls)
        local row,err=core:create(3,{scene_id=7,target_url="https://example.com"})
        assert.is_nil(row);assert.equals(403,err.status);assert.equals(2,calls)
    end)
    it("rejects unsafe URLs, invalid scene IDs, malformed or expired timestamps before allocating",function()
        for _,p in ipairs({{scene_id=1,target_url="javascript:alert(1)"},
            {scene_id=0,target_url="https://example.com"},{scene_id=4294967296,target_url="https://example.com"},
            {scene_id=1,target_url="https://example.com\r\nx: y"},
            {scene_id=1,target_url="https://example.com",expires_at="1970-01-01T00:00:00Z"},
            {scene_id=1,target_url="https://example.com",expires_at=false}}) do
            local row,err=core:create(1,p);assert.is_nil(row);assert.equals(400,err.status)
        end
        assert.equals(0,calls)
        assert(core:create(1,{scene_id=1,target_url="https://example.com",expires_at="2099-01-01T00:00:00Z"}))
    end)
    it("surfaces storage failures without treating them as missing data",function()
        core.tenant_model.authorized=function() return nil,"db down" end
        local _,err=core:create(1,{scene_id=1,target_url="https://example.com"})
        assert.equals(500,err.status)
    end)
    it("keeps explicit segments out of the worker pool and uses database step by default",function()
        local cursor=0
        local gen=Generator.new({db={query=function(_,sql,key,size)
            assert.equals(1,key);assert.matches("sequence_key",sql)
            size=size or 3
            cursor=cursor+size
            return {{segment_start=cursor-size+1,segment_end=cursor}}
        end}})
        assert.equals(1,gen:next_id())
        assert.same({start=4,["end"]=5},gen:allocate_segment(2))
        assert.same({2,3,6},gen:next_ids(3))
        assert.is_nil(gen:next_ids(0));assert.is_nil(gen:allocate_segment(1.5))
    end)
end)
