local helpers = require("tests.helpers")

describe("al.editor_commands.debug_without_publishing", function()
    local mod

    before_each(function()
        package.loaded["al.editor_commands.debug_without_publishing"] = nil
    end)

    after_each(function()
        package.loaded["dap"] = nil
    end)

    it("runs dap with justDebug overlay, preserving connection fields", function()
        local captured
        package.loaded["dap"] = {
            run = function(cfg)
                captured = cfg
            end,
        }
        mod = require("al.editor_commands.debug_without_publishing")

        mod({
            name = "Dev",
            server = "http://bc",
            serverInstance = "BC",
            tenant = "default",
            startupObjectId = 42,
        })

        assert.is_not_nil(captured)
        assert.is_true(captured.justDebug)
        assert.is_false(captured.publishOnly)
        assert.is_false(captured.isRad)
        assert.are.equal("launch", captured.request)
        assert.are.equal("http://bc", captured.server)
        assert.are.equal("BC", captured.serverInstance)
        assert.are.equal("default", captured.tenant)
        assert.are.equal(42, captured.startupObjectId)
    end)

    it("errors gracefully when nvim-dap is unavailable", function()
        package.loaded["dap"] = nil
        mod = require("al.editor_commands.debug_without_publishing")
        local notify = helpers.capture_notify()

        assert.has_no.errors(function()
            mod({ name = "Dev" })
        end)

        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("nvim%-dap is not available") then
                found = true
            end
        end
        assert.is_true(found)
        notify.restore()
    end)
end)
