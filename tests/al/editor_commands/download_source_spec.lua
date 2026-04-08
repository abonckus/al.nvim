local helpers = require("tests.helpers")

describe("al.editor_commands.download_source", function()
    local download_source

    before_each(function()
        package.loaded["al.editor_commands.download_source"] = nil
        download_source = require("al.editor_commands.download_source")
    end)

    it("sends al/downloadSource request", function()
        local client = helpers.make_mock_client({
            responses = { ["al/downloadSource"] = { result = { success = true } } },
        })
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        download_source()
        helpers.flush()
        assert.are.equal("al/downloadSource", client.requests[1].method)
        restore_lsp()
        notify.restore()
    end)

    it("shows error on failure", function()
        local client = helpers.make_mock_client({
            responses = { ["al/downloadSource"] = { result = { success = false } } },
        })
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        download_source()
        helpers.flush()
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("failed") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)
end)
