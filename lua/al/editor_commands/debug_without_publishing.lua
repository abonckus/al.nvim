local Util = require("al.utils")

--- Start a debug session against the already-deployed app, skipping the
--- local build + publish step (VS Code: "AL: Debug without publishing").
--- `config` is a launch configuration already merged with default_launch_cfg.
---@param config al.LaunchConfiguration
local debug_without_publishing = function(config)
    local ok, dap = pcall(require, "dap")
    if not ok then
        Util.error("nvim-dap is not available.")
        return
    end

    local cfg = vim.tbl_extend("force", config, {
        justDebug = true,
        publishOnly = false,
        isRad = false,
        request = "launch",
    })

    dap.run(cfg)
end

return debug_without_publishing
