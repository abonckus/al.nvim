describe("al.cmd", function()
    local cmd

    before_each(function()
        package.loaded["al.cmd"] = nil
        cmd = require("al.cmd")
    end)

    describe("parse", function()
        it("parses single command", function()
            local prefix, args = cmd.parse("build")
            assert.are.equal("build", prefix)
            assert.are.same({}, args)
        end)

        it("strips AL prefix", function()
            local prefix, args = cmd.parse("AL build")
            assert.are.equal("build", prefix)
            assert.are.same({}, args)
        end)

        it("parses command with args", function()
            local prefix, args = cmd.parse("runObject Page 22")
            assert.are.equal("runObject", prefix)
            assert.are.same({ "Page", "22" }, args)
        end)

        it("parses multi-word args", function()
            local prefix, args = cmd.parse("config My Server")
            assert.are.equal("config", prefix)
            assert.are.same({ "My", "Server" }, args)
        end)

        it("returns empty string for empty input", function()
            local prefix, args = cmd.parse("")
            assert.are.equal("", prefix)
            assert.are.same({}, args)
        end)

        it("handles trailing space for completion", function()
            local prefix, args = cmd.parse("config ")
            assert.are.equal("config", prefix)
            assert.are.same({ "" }, args)
        end)
    end)

    describe("complete", function()
        it("returns commands matching prefix", function()
            local results = cmd.complete(nil, "AL build")
            assert.is_true(vim.tbl_contains(results, "build"))
        end)

        it("returns all commands for empty prefix", function()
            local results = cmd.complete(nil, "AL ")
            assert.is_true(#results > 10)
        end)

        it("returns empty for known command with trailing space", function()
            local results = cmd.complete(nil, "AL config ")
            assert.are.same({}, results)
        end)
    end)

    describe("execute", function()
        it("shows error for empty command", function()
            local notified = false
            local orig = vim.notify
            vim.notify = function(msg)
                if msg:match("Usage:") then notified = true end
            end
            cmd.execute({ args = "" })
            assert.is_true(notified)
            vim.notify = orig
        end)

        it("shows error for unknown command", function()
            local notified = false
            local orig = vim.notify
            vim.notify = function(msg)
                if msg:match("Unknown command") then notified = true end
            end
            cmd.execute({ args = "nonexistent" })
            assert.is_true(notified)
            vim.notify = orig
        end)

        it("calls correct command handler", function()
            local called = false
            cmd.commands.definition = function() called = true end
            cmd.execute({ args = "definition" })
            assert.is_true(called)
        end)

        it("passes args to command handler", function()
            local received_args
            cmd.commands.symbolSearch = function(args) received_args = args end
            cmd.execute({ args = "symbolSearch Customer" })
            assert.are.same({ "Customer" }, received_args)
        end)
    end)
end)
