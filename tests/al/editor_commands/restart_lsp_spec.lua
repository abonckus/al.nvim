local helpers = require("tests.helpers")

describe("al.editor_commands.restart_lsp", function()
    local restart_lsp

    before_each(function()
        package.loaded["al.editor_commands.restart_lsp"] = nil
        restart_lsp = require("al.editor_commands.restart_lsp")
    end)

    it("warns when no AL server running", function()
        local restore = helpers.stub_get_clients({})
        local notify = helpers.capture_notify()
        restart_lsp()
        local found = false
        for _, m in ipairs(notify.messages) do
            if m.msg:match("No AL language server") then found = true end
        end
        assert.is_true(found)
        restore()
        notify.restore()
    end)

    it("stops all al_ls clients", function()
        local stopped = {}
        local make_client = function(id)
            return {
                id = id,
                name = "al_ls",
                stop = function(self) table.insert(stopped, self.id) end,
            }
        end
        local restore = helpers.stub_get_clients({
            make_client(1),
            make_client(2),
        })
        local notify = helpers.capture_notify()
        restart_lsp()
        assert.are.same({ 1, 2 }, stopped)
        restore()
        notify.restore()
    end)
end)
