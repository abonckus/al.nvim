local helpers = require("tests.helpers")

describe("al.editor_commands.download_symbols", function()
    local download_symbols

    before_each(function()
        package.loaded["al.editor_commands.download_symbols"] = nil
        download_symbols = require("al.editor_commands.download_symbols")
    end)

    it("sends al/downloadSymbols with correct params", function()
        local client = helpers.make_mock_client()
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        download_symbols({ name = "Dev", server = "http://bc" })
        helpers.flush()
        assert.are.equal(1, #client.requests)
        assert.are.equal("al/downloadSymbols", client.requests[1].method)
        assert.are.equal("Dev", client.requests[1].params.configuration.name)
        restore_lsp()
        notify.restore()
    end)

    it("shows success message on result.success", function()
        local client = helpers.make_mock_client({
            responses = { ["al/downloadSymbols"] = { result = { success = true } } },
        })
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        download_symbols({ name = "Dev" })
        helpers.flush()
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("downloaded") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)

    it("shows error on failure", function()
        local client = helpers.make_mock_client({
            responses = { ["al/downloadSymbols"] = { result = { success = false } } },
        })
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        download_symbols({ name = "Dev" })
        helpers.flush()
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("Could not download") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)
end)
