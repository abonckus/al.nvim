local helpers = require("tests.helpers")

describe("al.ui", function()
    local ui

    before_each(function()
        package.loaded["al.ui"] = nil
        ui = require("al.ui")
    end)

    describe("show_input_username", function()
        it("calls on_submit with value when input provided", function()
            local restore = helpers.stub_ui_input("admin")
            local result
            ui.show_input_username(function(v) result = v end, function() end)
            assert.are.equal("admin", result)
            restore()
        end)

        it("calls on_cancel when input is nil", function()
            local restore = helpers.stub_ui_input(nil)
            local cancelled = false
            ui.show_input_username(function() end, function() cancelled = true end)
            assert.is_true(cancelled)
            restore()
        end)

        it("calls on_cancel when input is empty", function()
            local restore = helpers.stub_ui_input("")
            local cancelled = false
            ui.show_input_username(function() end, function() cancelled = true end)
            assert.is_true(cancelled)
            restore()
        end)
    end)

    describe("show_input_password", function()
        it("calls on_submit with value from inputsecret", function()
            local restore = helpers.stub_inputsecret("secret123")
            local result
            ui.show_input_password(function(v) result = v end, function() end)
            helpers.flush()
            assert.are.equal("secret123", result)
            restore()
        end)

        it("calls on_cancel when inputsecret returns empty", function()
            local restore = helpers.stub_inputsecret("")
            local cancelled = false
            ui.show_input_password(function() end, function() cancelled = true end)
            helpers.flush()
            assert.is_true(cancelled)
            restore()
        end)
    end)
end)
