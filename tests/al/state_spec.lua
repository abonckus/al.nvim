local helpers = require("tests.helpers")

describe("al.state", function()
    local State

    before_each(function()
        package.loaded["al.state"] = nil
        State = require("al.state")
    end)

    describe("set_config", function()
        it("sets active_config and active_config_name", function()
            local cfg = { name = "MyServer", server = "http://localhost" }
            State.set_config(cfg)
            assert.are.equal(cfg, State.active_config)
            assert.are.equal("MyServer", State.active_config_name)
        end)
    end)

    describe("clear_config", function()
        it("resets both fields to nil", function()
            State.set_config({ name = "Test" })
            State.clear_config()
            assert.is_nil(State.active_config)
            assert.is_nil(State.active_config_name)
        end)
    end)

    describe("resolve_config", function()
        it("returns active_config immediately if set", function()
            local cfg = { name = "Active" }
            State.set_config(cfg)
            local result
            coroutine.resume(coroutine.create(function()
                result = State.resolve_config({ { name = "Other" } })
            end))
            assert.are.equal(cfg, result)
        end)

        it("prompts with vim.ui.select when no active config", function()
            local configs = { { name = "ServerA" }, { name = "ServerB" } }
            local restore = helpers.stub_ui_select(2)
            local result
            coroutine.resume(coroutine.create(function()
                result = State.resolve_config(configs)
            end))
            assert.are.equal("ServerB", result.name)
            assert.are.equal("ServerB", State.active_config_name)
            restore()
        end)

        it("returns nil when user cancels selection", function()
            local restore = helpers.stub_ui_select(nil)
            local result = "sentinel"
            coroutine.resume(coroutine.create(function()
                result = State.resolve_config({ { name = "A" } })
            end))
            assert.is_nil(result)
            assert.is_nil(State.active_config)
            restore()
        end)

        it("errors when not in coroutine", function()
            assert.has_error(function()
                State.resolve_config({ { name = "A" } })
            end)
        end)
    end)

    describe("statusline", function()
        it("returns config name when set", function()
            State.set_config({ name = "Dev" })
            local restore = helpers.stub_get_clients({})
            local s = State.statusline()
            assert.are.equal("Dev", s.config)
            restore()
        end)

        it("returns nil config when not set", function()
            local restore = helpers.stub_get_clients({})
            local s = State.statusline()
            assert.is_nil(s.config)
            restore()
        end)

        it("returns lsp=false when no al_ls client", function()
            local restore = helpers.stub_get_clients({})
            local s = State.statusline()
            assert.is_false(s.lsp)
            restore()
        end)

        it("returns lsp=true when al_ls client attached", function()
            local restore = helpers.stub_get_clients({ { name = "al_ls", id = 1 } })
            local s = State.statusline()
            assert.is_true(s.lsp)
            restore()
        end)
    end)
end)
