local helpers = require("tests.helpers")

describe("al.editor_commands.publish", function()
    local publish

    before_each(function()
        package.loaded["al.editor_commands.publish"] = nil
        package.loaded["al.editor_commands.auth"] = nil
        package.loaded["al.editor_commands.auth"] = function() return "success" end
        package.loaded["al.multiproject"] = {
            project_for_buf = function() return "/test/project" end,
            workspace_root = function() return nil end,
        }
        publish = require("al.editor_commands.publish")
    end)

    after_each(function()
        package.loaded["al.editor_commands.auth"] = nil
        package.loaded["al.multiproject"] = nil
    end)

    it("sends al/fullDependencyPublish on auth success", function()
        local client = helpers.make_mock_client()
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        publish({ name = "Dev", server = "http://bc" })
        helpers.flush()
        assert.are.equal(1, #client.requests)
        assert.are.equal("al/fullDependencyPublish", client.requests[1].method)
        assert.are.equal("Dev", client.requests[1].params.configuration.name)
        restore_lsp()
        notify.restore()
    end)

    it("aborts with warning on auth cancellation", function()
        package.loaded["al.editor_commands.auth"] = function() return "cancelled" end
        package.loaded["al.editor_commands.publish"] = nil
        publish = require("al.editor_commands.publish")
        local client = helpers.make_mock_client()
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        publish({ name = "Dev" })
        assert.are.equal(0, #client.requests)
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("cancelled") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)

    it("aborts with error on auth failure", function()
        package.loaded["al.editor_commands.auth"] = function() return "fail" end
        package.loaded["al.editor_commands.publish"] = nil
        publish = require("al.editor_commands.publish")
        local client = helpers.make_mock_client()
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        publish({ name = "Dev" })
        assert.are.equal(0, #client.requests)
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("failed") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)

    it("shows error when no LSP client", function()
        local restore_lsp = helpers.stub_lsp_client(nil)
        local notify = helpers.capture_notify()
        publish({ name = "Dev" })
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("No AL language server") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)
end)
