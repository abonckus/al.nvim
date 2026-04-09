local helpers = require("tests.helpers")

describe("al.editor_commands.open_in_browser", function()
    local open_in_browser
    local captured_url
    local restore_jobstart
    local restore_ui_open

    before_each(function()
        package.loaded["al.editor_commands.open_in_browser"] = nil
        open_in_browser = require("al.editor_commands.open_in_browser")
        captured_url = nil

        -- Mock both paths so no browser actually opens
        local orig_jobstart = vim.fn.jobstart
        vim.fn.jobstart = function(cmd, opts)
            -- cmd is { "rundll32", "url.dll,FileProtocolHandler", url }
            if type(cmd) == "table" and cmd[1] == "rundll32" then
                captured_url = cmd[3]
            end
            return 0
        end
        restore_jobstart = function()
            vim.fn.jobstart = orig_jobstart
        end

        local orig_ui_open = vim.ui.open
        vim.ui.open = function(url)
            captured_url = url
        end
        restore_ui_open = function()
            vim.ui.open = orig_ui_open
        end
    end)

    after_each(function()
        restore_jobstart()
        restore_ui_open()
    end)

    it("constructs on-prem URL with server, port, instance, tenant", function()
        local notify = helpers.capture_notify()
        open_in_browser({
            server = "http://bcserver",
            port = 7049,
            serverInstance = "BC",
            tenant = "default",
            startupCompany = "",
        })
        assert.are.equal("http://bcserver:7049/BC/?tenant=default", captured_url)
        notify.restore()
    end)

    it("constructs SaaS URL when environmentName is set", function()
        local notify = helpers.capture_notify()
        open_in_browser({
            server = "http://bcserver",
            port = 7049,
            serverInstance = "BC",
            tenant = "default",
            startupCompany = "",
            environmentName = "sandbox",
        })
        assert.are.equal("https://businesscentral.dynamics.com/sandbox", captured_url)
        notify.restore()
    end)

    it("omits port when 0", function()
        local notify = helpers.capture_notify()
        open_in_browser({
            server = "http://bcserver",
            port = 0,
            serverInstance = "BC",
            tenant = "default",
            startupCompany = "",
        })
        assert.are.equal("http://bcserver/BC/?tenant=default", captured_url)
        notify.restore()
    end)

    it("URL-encodes company name", function()
        local notify = helpers.capture_notify()
        open_in_browser({
            server = "http://bcserver",
            port = 7049,
            serverInstance = "BC",
            tenant = "default",
            startupCompany = "My Company",
        })
        assert.is_truthy(captured_url:match("company=My%%20Company"))
        notify.restore()
    end)
end)
