describe("al.integrations.dap.should_build", function()
    local dap_int

    before_each(function()
        package.loaded["al.integrations.dap"] = nil
        dap_int = require("al.integrations.dap")
    end)

    it("skips build when justDebug is true", function()
        assert.is_false(dap_int.should_build({ justDebug = true }))
    end)

    it("builds when justDebug is false", function()
        assert.is_true(dap_int.should_build({ justDebug = false }))
    end)

    it("builds when justDebug is absent", function()
        assert.is_true(dap_int.should_build({}))
    end)
end)
