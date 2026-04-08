local helpers = require("tests.helpers")

describe("al.editor_commands.generate_permission_set", function()
    local generate_permission_set

    before_each(function()
        package.loaded["al.editor_commands.generate_permission_set"] = nil
        package.loaded["al.multiproject"] = {
            project_for_buf = function() return "/test/project" end,
            workspace_root = function() return nil end,
        }
        generate_permission_set = require("al.editor_commands.generate_permission_set")
    end)

    after_each(function()
        package.loaded["al.multiproject"] = nil
    end)

    it("sends al/generatePermissionSetInALObject with workspace path", function()
        local client = helpers.make_mock_client({
            responses = { ["al/generatePermissionSetInALObject"] = { result = { success = true } } },
        })
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        generate_permission_set()
        helpers.flush()
        assert.are.equal("al/generatePermissionSetInALObject", client.requests[1].method)
        assert.are.equal("/test/project", client.requests[1].params.currentWorkspacePath)
        restore_lsp()
        notify.restore()
    end)

    it("shows error when no LSP client", function()
        local restore_lsp = helpers.stub_lsp_client(nil)
        local notify = helpers.capture_notify()
        generate_permission_set()
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("No AL language server") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)
end)
