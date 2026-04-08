local helpers = require("tests.helpers")

describe("al.editor_commands.config", function()
    local set_config, State

    before_each(function()
        package.loaded["al.state"] = nil
        package.loaded["al.editor_commands.config"] = nil
        State = require("al.state")
        set_config = require("al.editor_commands.config")
    end)

    local configs = {
        { name = "ServerA", server = "http://a" },
        { name = "ServerB", server = "http://b" },
    }

    it("sets config by name when args match", function()
        local notify = helpers.capture_notify()
        set_config({ "ServerB" }, configs)
        assert.are.equal("ServerB", State.active_config_name)
        notify.restore()
    end)

    it("shows error when name not found", function()
        local notify = helpers.capture_notify()
        set_config({ "NonExistent" }, configs)
        assert.is_nil(State.active_config)
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("not found") then found = true end
        end
        assert.is_true(found)
        notify.restore()
    end)

    it("shows picker when no args", function()
        local restore = helpers.stub_ui_select(1)
        local notify = helpers.capture_notify()
        set_config({}, configs)
        assert.are.equal("ServerA", State.active_config_name)
        restore()
        notify.restore()
    end)

    it("shows error when configs empty", function()
        local notify = helpers.capture_notify()
        set_config({}, {})
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("No launch configurations") then found = true end
        end
        assert.is_true(found)
        notify.restore()
    end)
end)
