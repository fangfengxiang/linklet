-- spec/id_generator_spec.lua
-- 发号器测试：号段分配、本地消耗、跳号容忍
-- ID generator tests: segment allocation, local consumption, gap tolerance

local IdGenerator = require("linklet.id.generator")
local helper = require("helper")

describe("IdGenerator", function()
    describe("segment allocation", function()
        it("allocates a segment from PostgreSQL on first call", function()
            local db = helper.mock_db(function(sql, ...)
                return {{segment_start = "1000", segment_end = "1999"}}
            end)
            local gen = IdGenerator.new({db = db, segment_size = 1000})

            local id = gen:next_id()

            assert.equals(1000, id)
            assert.equals(1, db.query_count)
        end)

        it("returns next ID from local segment without DB access", function()
            local db = helper.mock_db(function(sql, ...)
                return {{segment_start = "1000", segment_end = "1999"}}
            end)
            local gen = IdGenerator.new({db = db, segment_size = 1000})

            -- 第一次调用分配号段
            local id1 = gen:next_id()
            local id2 = gen:next_id()
            local id3 = gen:next_id()

            assert.equals(1000, id1)
            assert.equals(1001, id2)
            assert.equals(1002, id3)
            -- 只访问了一次数据库 / only one DB access
            assert.equals(1, db.query_count)
        end)

        it("allocates new segment when local segment is exhausted", function()
            local call_count = 0
            local db = helper.mock_db(function(sql, ...)
                call_count = call_count + 1
                if call_count == 1 then
                    return {{segment_start = "1000", segment_end = "1001"}}
                else
                    return {{segment_start = "2000", segment_end = "2999"}}
                end
            end)
            local gen = IdGenerator.new({db = db, segment_size = 2})

            local id1 = gen:next_id()  -- 1000
            local id2 = gen:next_id()  -- 1001
            local id3 = gen:next_id()  -- needs new segment → 2000

            assert.equals(1000, id1)
            assert.equals(1001, id2)
            assert.equals(2000, id3)
            assert.equals(2, db.query_count)
        end)
    end)

    describe("concurrent safety", function()
        it("two generators get non-overlapping segments", function()
            local counter = 0
            local db = helper.mock_db(function(sql, ...)
                counter = counter + 1000
                return {{segment_start = tostring(counter - 999), segment_end = tostring(counter)}}
            end)

            local gen1 = IdGenerator.new({db = db, segment_size = 1000})
            local gen2 = IdGenerator.new({db = db, segment_size = 1000})

            local id1 = gen1:next_id()
            local id2 = gen2:next_id()

            assert.not_equals(id1, id2)
            assert.truthy(id1 < id2 or id2 < id1)
            -- 两个号段不重叠 / segments don't overlap
            local s1 = gen1:status()
            local s2 = gen2:status()
            assert.truthy(s1.start ~= s2.start)
        end)
    end)

    describe("gap tolerance", function()
        it("allows gaps after reset", function()
            local call_count = 0
            local db = helper.mock_db(function(sql, ...)
                call_count = call_count + 1
                if call_count == 1 then
                    return {{segment_start = "5000", segment_end = "5999"}}
                else
                    return {{segment_start = "10000", segment_end = "10999"}}
                end
            end)
            local gen = IdGenerator.new({db = db, segment_size = 1000})

            local id1 = gen:next_id()  -- 5000
            gen:reset()                -- simulate worker restart
            local id2 = gen:next_id()  -- 10000 (new segment)

            assert.equals(5000, id1)
            assert.equals(10000, id2)
            -- IDs 5001-5999 are lost (gaps)
            assert.truthy(id2 > id1 + 1, "gap expected")
        end)
    end)

    describe("status", function()
        it("reports correct segment status", function()
            local db = helper.mock_db(function()
                return {{segment_start = "1000", segment_end = "1999"}}
            end)
            local gen = IdGenerator.new({db = db, segment_size = 1000})

            gen:next_id()  -- allocate segment

            local status = gen:status()
            assert.equals(1000, status.start)
            assert.equals(1999, status["end"])
            assert.equals(1001, status.cursor)
            assert.equals(999, status.remaining)
        end)
    end)

    describe("error handling", function()
        it("returns error if DB query fails", function()
            local db = helper.mock_db(nil)
            db.query = function() return nil, "connection refused" end
            local gen = IdGenerator.new({db = db, segment_size = 1000})

            local id, err = gen:next_id()
            assert.is_nil(id)
            assert.truthy(err)
        end)

        it("errors if db is nil in constructor", function()
            assert.has_error(function()
                IdGenerator.new({})
            end)
        end)
    end)
end)
