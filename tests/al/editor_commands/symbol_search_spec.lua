local helpers = require("tests.helpers")

describe("al.editor_commands.symbol_search", function()
    local symbol_search

    before_each(function()
        package.loaded["al.editor_commands.symbol_search"] = nil
        symbol_search = require("al.editor_commands.symbol_search")
    end)

    it("prompts for query when no args", function()
        local client = helpers.make_mock_client()
        local restore_lsp = helpers.stub_lsp_client(client)
        local prompted = false
        local orig = vim.ui.input
        vim.ui.input = function(opts, cb)
            prompted = true
            cb(nil)
        end
        symbol_search({})
        assert.is_true(prompted)
        vim.ui.input = orig
        restore_lsp()
    end)

    it("sends al/symbolSearch with query from args", function()
        local client = helpers.make_mock_client({
            responses = { ["al/symbolSearch"] = { result = {} } },
        })
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        symbol_search({ "Customer" })
        helpers.flush()
        assert.are.equal("al/symbolSearch", client.requests[1].method)
        assert.are.equal("Customer", client.requests[1].params.query)
        restore_lsp()
        notify.restore()
    end)

    it("shows no symbols message when empty result", function()
        local client = helpers.make_mock_client({
            responses = { ["al/symbolSearch"] = { result = {} } },
        })
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        symbol_search({ "nonexistent" })
        helpers.flush()
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("No symbols found") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)
end)
