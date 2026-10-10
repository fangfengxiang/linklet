-- spec/base_model_spec.lua
-- 模型基类测试 / Base model tests

local helper = require("helper")
local BaseModel = require("models.base_model")

describe("BaseModel", function()
    local model, db

    before_each(function()
        db = helper.mock_db(function(sql, ...)
            return {{id = 1, name = "test", code = "aB9xK2"}}
        end)
        model = BaseModel.new(db, "sl_link")
    end)

    describe("query", function()
        it("executes SQL and returns result", function()
            local res = model:query("SELECT 1")
            assert.truthy(res)
            assert.equals(1, db.query_count)
        end)
    end)

    describe("find_by_id", function()
        it("finds a row by primary key", function()
            local row = model:find_by_id(1)
            assert.truthy(row)
            assert.equals(1, row.id)
        end)

        it("returns nil when no row found", function()
            db.query = function() return {} end
            local row = model:find_by_id(999)
            assert.is_nil(row)
        end)

        it("propagates database errors", function()
            db.query = function() return nil, "connection failed" end
            local row, err = model:find_by_id(1)
            assert.is_nil(row)
            assert.equals("connection failed", err)
        end)
    end)

    describe("insert", function()
        it("inserts a row and returns it", function()
            db.query = function(self, sql, ...)
                local args = {...}
                return {{id = 1, code = args[1], target_url = args[2], scene_id = args[3]}}
            end
            local row = model:insert({code = "aB9xK2", target_url = "https://example.com", scene_id = 1})
            assert.truthy(row)
            assert.equals("aB9xK2", row.code)
        end)

        it("returns nil on database error", function()
            db.query = function() return nil, "constraint violation" end
            local row, err = model:insert({code = "dup", target_url = "https://example.com"})
            assert.is_nil(row)
            assert.equals("constraint violation", err)
        end)
    end)

    describe("find_where", function()
        it("builds SQL with conditions", function()
            local captured_sql
            db.query = function(self, sql, ...)
                captured_sql = sql
                return {{id = 1}}
            end
            model:find_where("status = $1", {1}, 10)
            assert.matches("WHERE", captured_sql)
            assert.matches("LIMIT", captured_sql)
        end)

        it("returns rows from query", function()
            db.query = function() return {{id = 1}, {id = 2}} end
            local rows = model:find_where("status = $1", {1})
            assert.truthy(rows)
            assert.equals(2, #rows)
        end)
    end)

    describe("update", function()
        it("updates rows by condition", function()
            local captured_sql
            db.query = function(self, sql, ...)
                captured_sql = sql
                return {{id = 1, status = 2}}
            end
            local res = model:update({status = 2}, "code = $1", {"aB9xK2"})
            assert.matches("UPDATE", captured_sql)
            assert.matches("WHERE", captured_sql)
        end)
    end)

    describe("new", function()
        it("errors when db is nil", function()
            assert.has_error(function()
                BaseModel.new(nil, "test")
            end)
        end)

        it("creates instance with table_name", function()
            local m = BaseModel.new(db, "my_table")
            assert.equals("my_table", m.table_name)
        end)
    end)
end)
