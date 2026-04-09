local helpers = require("tests.helpers")

describe("al.editor_commands.event_publishers", function()
    local event_publishers

    before_each(function()
        package.loaded["al.editor_commands.event_publishers"] = nil
        event_publishers = require("al.editor_commands.event_publishers")
    end)

    it("sends al/getEventPublishersRequest with format Detailed", function()
        local client = helpers.make_mock_client({
            responses = {
                ["al/getEventPublishersRequest"] = {
                    result = { { name = "OnAfterPost", signature = "procedure OnAfterPost()", path = "/test.al" } },
                },
            },
        })
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        event_publishers()
        helpers.flush()
        assert.are.equal("al/getEventPublishersRequest", client.requests[1].method)
        assert.are.equal("Detailed", client.requests[1].params.format)
        restore_lsp()
        notify.restore()
    end)

    it("shows no event publishers message when empty", function()
        local client = helpers.make_mock_client({
            responses = { ["al/getEventPublishersRequest"] = { result = {} } },
        })
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        event_publishers()
        helpers.flush()
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("No event publishers") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)
end)
