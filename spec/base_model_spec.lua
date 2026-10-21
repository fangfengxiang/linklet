local Base = require("linklet.repository.base")

describe("Repository base", function()
    it("requires an injected database", function()
        assert.has_error(function() Base.new(nil, "sl_tenant") end)
    end)

    it("looks up a primary key through the injected database", function()
        local repository = Base.new({query = function(_, sql, id)
            assert.matches("sl_tenant", sql)
            return {{id = id, name = "tenant"}}
        end}, "sl_tenant")
        assert.equals(7, repository:find_by_id(7).id)
    end)

    it("distinguishes missing rows from database failures", function()
        local repository = Base.new({query = function() return {} end}, "sl_tenant")
        local row, err = repository:find_by_id(7)
        assert.is_nil(row)
        assert.is_nil(err)
        repository.db.query = function() return nil, "unavailable" end
        row, err = repository:find_by_id(7)
        assert.is_nil(row)
        assert.equals("unavailable", err)
    end)
end)
