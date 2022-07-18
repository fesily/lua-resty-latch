describe("resty.latch", function()
    local latch = require("resty.latch")
    describe("new", function()
        describe("check arguments", function()
            it("1", function()
                assert.is_nil(latch.new())
            end)
            it("2", function()
                assert.is_nil(latch.new('test'))
            end)
            it("3", function()
                assert.is_nil(latch.new('test', 'k'))
            end)

        end)

        it("no shdict", function()
            local shdict = ngx.shared['test']
            ngx.shared['test'] = nil
            local la, err = latch.new("test", "k", 1)
            assert.is_nil(la, err)
            ngx.shared['test'] = shdict
        end)

        describe("default new", function()
            local la, err = latch.new("test", "k", 1)
            it("create", function()
                assert.is_not_nil(la, err)
            end)
            it("create again", function()
                local la, err = latch.new("test", "k", 1)
                assert.is_nil(la, err)
                assert.is_equal(err, 'exists')
            end)
            it("create again when count down", function()
                la:count_down()
                la, err = latch.new("test", "k", 1)
                assert.is_not_nil(la, err)
                local value, err = la.dict:get(la.key)
                assert.is_equal(value, 1, err)
            end)
        end)
    end)

    describe("wait", function()
        it("once", function()
            local la, err = latch.new("test", "k1", 1)
            assert(la, err)
            local seq = {}
            local th = ngx.thread.spawn(function()
                la:wait()
                seq[2] = 2
            end)
            seq[1] = 1
            la:count_down()
            seq[3] = 3
            ngx.sleep(0.1)
            assert.is_same(seq, { 1, 2, 3 })
            assert(la:is_ready())
        end)
        it("twice", function()
            local la, err = latch.new("test", "k1", 1)
            assert(la, err)
            local seq = 0
            local fn = function()
                la:wait()
                seq = seq + 1
            end
            local th = ngx.thread.spawn(fn)
            local th1 = ngx.thread.spawn(fn)
            la:count_down()
            ngx.sleep(0.1)
            assert.is_equal(seq, 2)
            assert(la:is_ready())
        end)
    end)

end)
