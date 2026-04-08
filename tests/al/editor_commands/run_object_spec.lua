local helpers = require("tests.helpers")

describe("al.editor_commands.run_object", function()
    local run_object

    before_each(function()
        package.loaded["al.editor_commands.run_object"] = nil
        run_object = require("al.editor_commands.run_object")
    end)

    it("sends al/runObject with config defaults", function()
        local client = helpers.make_mock_client()
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        run_object({ name = "Dev", startupObjectType = "Page", startupObjectId = 22 }, {})
        helpers.flush()
        assert.are.equal("al/runObject", client.requests[1].method)
        assert.are.equal("Page", client.requests[1].params.configuration.startupObjectType)
        assert.are.equal(22, client.requests[1].params.configuration.startupObjectId)
        restore_lsp()
        notify.restore()
    end)

    it("overrides object type and id from args", function()
        local client = helpers.make_mock_client()
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        local config = { name = "Dev", startupObjectType = "Page", startupObjectId = 22 }
        run_object(config, { "Report", "50100" })
        helpers.flush()
        assert.are.equal("Report", client.requests[1].params.configuration.startupObjectType)
        assert.are.equal(50100, client.requests[1].params.configuration.startupObjectId)
        -- Original not mutated
        assert.are.equal("Page", config.startupObjectType)
        assert.are.equal(22, config.startupObjectId)
        restore_lsp()
        notify.restore()
    end)

    it("shows error when no LSP client", function()
        local restore_lsp = helpers.stub_lsp_client(nil)
        local notify = helpers.capture_notify()
        run_object({ name = "Dev" }, {})
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("No AL language server") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)
end)
