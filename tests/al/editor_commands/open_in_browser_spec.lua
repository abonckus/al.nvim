local helpers = require("tests.helpers")

describe("al.editor_commands.open_in_browser", function()
    local open_in_browser

    before_each(function()
        package.loaded["al.editor_commands.open_in_browser"] = nil
        open_in_browser = require("al.editor_commands.open_in_browser")
    end)

    it("constructs on-prem URL with server, port, instance, tenant", function()
        local captured = helpers.stub_ui_open()
        local notify = helpers.capture_notify()
        open_in_browser({
            server = "http://bcserver", port = 7049, serverInstance = "BC",
            tenant = "default", startupCompany = "",
        })
        assert.are.equal("http://bcserver:7049/BC/?tenant=default", captured.url)
        captured.restore()
        notify.restore()
    end)

    it("constructs SaaS URL when environmentName is set", function()
        local captured = helpers.stub_ui_open()
        local notify = helpers.capture_notify()
        open_in_browser({
            server = "http://bcserver", port = 7049, serverInstance = "BC",
            tenant = "default", startupCompany = "", environmentName = "sandbox",
        })
        assert.are.equal("https://businesscentral.dynamics.com/sandbox", captured.url)
        captured.restore()
        notify.restore()
    end)

    it("omits port when 0", function()
        local captured = helpers.stub_ui_open()
        local notify = helpers.capture_notify()
        open_in_browser({
            server = "http://bcserver", port = 0, serverInstance = "BC",
            tenant = "default", startupCompany = "",
        })
        assert.are.equal("http://bcserver/BC/?tenant=default", captured.url)
        captured.restore()
        notify.restore()
    end)

    it("URL-encodes company name", function()
        local captured = helpers.stub_ui_open()
        local notify = helpers.capture_notify()
        open_in_browser({
            server = "http://bcserver", port = 7049, serverInstance = "BC",
            tenant = "default", startupCompany = "My Company",
        })
        assert.is_truthy(captured.url:match("company=My%%20Company"))
        captured.restore()
        notify.restore()
    end)
end)
