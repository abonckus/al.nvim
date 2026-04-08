local helpers = require("tests.helpers")

describe("al.editor_commands.refresh_symbols", function()
    local refresh_symbols

    before_each(function()
        package.loaded["al.editor_commands.refresh_symbols"] = nil
        package.loaded["al.multiproject"] = {
            project_for_buf = function() return "/test/project" end,
            workspace_root = function() return nil end,
        }
        refresh_symbols = require("al.editor_commands.refresh_symbols")
    end)

    after_each(function()
        package.loaded["al.multiproject"] = nil
    end)

    it("sends al/refreshSymbolReferencesRequest with correct params", function()
        local client = helpers.make_mock_client()
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        refresh_symbols()
        helpers.flush()
        assert.are.equal("al/refreshSymbolReferencesRequest", client.requests[1].method)
        assert.is_truthy(client.requests[1].params.appPath:match(".alpackages"))
        assert.are.same({ "/test/project" }, client.requests[1].params.folders)
        restore_lsp()
        notify.restore()
    end)
end)
