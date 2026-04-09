local helpers = require("tests.helpers")

describe("al.editor_commands.dependencies", function()
    local dependencies

    before_each(function()
        package.loaded["al.editor_commands.dependencies"] = nil
        package.loaded["al.multiproject"] = {
            project_for_buf = function() return "/test/project" end,
            workspace_root = function() return nil end,
        }
        dependencies = require("al.editor_commands.dependencies")
    end)

    after_each(function()
        package.loaded["al.multiproject"] = nil
    end)

    it("sends al/getPackageDependencies", function()
        local client = helpers.make_mock_client({
            responses = {
                ["al/getPackageDependencies"] = {
                    result = { { appName = "Base", appPublisher = "Microsoft", appVersion = "1.0", appId = "abc" } },
                },
            },
        })
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        dependencies()
        helpers.flush()
        assert.are.equal("al/getPackageDependencies", client.requests[1].method)
        restore_lsp()
        notify.restore()
    end)

    it("shows no dependencies message when empty", function()
        local client = helpers.make_mock_client({
            responses = { ["al/getPackageDependencies"] = { result = {} } },
        })
        local restore_lsp = helpers.stub_lsp_client(client)
        local notify = helpers.capture_notify()
        dependencies()
        helpers.flush()
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("No package dependencies") then found = true end
        end
        assert.is_true(found)
        restore_lsp()
        notify.restore()
    end)
end)
