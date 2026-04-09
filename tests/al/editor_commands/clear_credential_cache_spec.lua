local helpers = require("tests.helpers")

describe("al.editor_commands.clear_credential_cache", function()
    local clear_credential_cache

    before_each(function()
        package.loaded["al.editor_commands.clear_credential_cache"] = nil
        clear_credential_cache = require("al.editor_commands.clear_credential_cache")
    end)

    it("sends al/clearCredentialsCache request with correct params", function()
        local client = helpers.make_mock_client()
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        clear_credential_cache({ name = "Dev", server = "http://bc" })
        helpers.flush()
        assert.are.equal(1, #client.requests)
        assert.are.equal("al/clearCredentialsCache", client.requests[1].method)
        assert.are.equal("Dev", client.requests[1].params.configuration.name)
        restore_lsp()
        notify.restore()
    end)

    it("shows error when no LSP client attached", function()
        local restore_lsp = helpers.stub_lsp_client(nil)
        local notify = helpers.capture_notify()
        clear_credential_cache({ name = "Dev" })
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("No AL language server") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)

    it("shows error message on request failure", function()
        local client = helpers.make_mock_client({
            responses = { ["al/clearCredentialsCache"] = { err = { message = "server error" } } },
        })
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        clear_credential_cache({ name = "Dev" })
        helpers.flush()
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("server error") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)
end)
