local Runtime = require("linklet.repository.runtime")
local Errors = require("linklet.repository.errors")

describe("Runtime storage capabilities", function()
    it("reserves and normalizes an atomic durable segment", function()
        local runtime = Runtime.new({query = function(_, sql, key, size)
            assert.matches("UPDATE sl_id_sequence", sql, 1, true)
            assert.equals(1, key)
            assert.equals(10, size)
            return {{segment_start="100",segment_end="109"}}
        end})
        assert.same({start=100,["end"]=109}, runtime:reserve_segment(1,10))
    end)

    it("reports exhaustion, malformed allocation and storage failure distinctly", function()
        local db = {query=function() return {} end}
        local runtime = Runtime.new(db)
        local segment, err = runtime:reserve_segment(1)
        assert.is_nil(segment); assert.equals("sequence_exhausted",err)
        db.query=function() return {{segment_start="broken",segment_end="109"}} end
        segment,err=runtime:reserve_segment(1)
        assert.is_nil(segment); assert.equals("unavailable",err)
        db.query=function() return nil,"private connection detail" end
        segment,err=runtime:reserve_segment(1)
        assert.is_nil(segment); assert.equals("unavailable",err)
    end)

    it("preserves a durable revision without numeric precision loss", function()
        local db = {query=function() return {{cache_revision="9007199254740993"}} end}
        local runtime=Runtime.new(db)
        assert.equals("9007199254740993",runtime:current_revision())
        db.query=function() return {{cache_revision="not a revision"}} end
        local revision,err=runtime:current_revision()
        assert.is_nil(revision);assert.equals("unavailable",err)
        db.query=function() return {} end
        revision,err=runtime:current_revision()
        assert.is_nil(revision);assert.equals("unavailable",err)
    end)

    it("requires the switched schema for readiness", function()
        local db={query=function() return {{ready=1}} end}
        local runtime=Runtime.new(db)
        assert.is_true(runtime:health())
        db.query=function() return {} end
        local healthy,err=runtime:health()
        assert.is_nil(healthy);assert.equals("unavailable",err)
    end)

    it("converts backend failures into stable domain error codes", function()
        assert.is_nil(Errors.normalize(nil))
        assert.equals("group_domain_locked",
            Errors.normalize("ERROR: group with links cannot change domain or be deleted"))
        assert.equals("domain_bound", Errors.normalize("ERROR: domain is still bound to a group"))
        assert.equals("domain_unavailable", Errors.normalize("ERROR: domain must be deployed"))
        assert.equals("invalid_grants", Errors.normalize("ERROR: grants must reference existing groups"))
        assert.equals("conflict", Errors.normalize("ERROR: duplicate key value violates unique constraint"))
        assert.equals("unavailable", Errors.normalize("secret host/password diagnostic"))
        assert.equals("group_domain_locked", Errors.normalize("group_domain_locked"))
        assert.equals("unavailable", Errors.normalize("connection failed\nDETAIL: domain must be deployed"))
    end)
end)
