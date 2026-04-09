local Config = require("al.config")
local Util = require("al.utils")
local Lsp = require("al.lsp")

---@param config al.LaunchConfiguration
---@param args string[]
local run_object = function(config, args)
    local buf = vim.api.nvim_get_current_buf()
    local client = Lsp.get_client_for_buf(buf)
    if not client then
        Util.error("No AL language server attached to the current buffer.")
        return
    end

    -- Override startup object from args: :AL runObject Page 22
    if args and #args >= 2 then
        config = vim.deepcopy(config)
        config.startupObjectType = args[1]
        config.startupObjectId = tonumber(args[2]) or config.startupObjectId
    end

    local params = {
        configuration = config,
        browserInfo = {
            browser = Config.lsp.browser,
            incognito = false,
        },
    }

    client:request("al/runObject", params, function(err, result)
        if err then
            Util.error("Run object failed: " .. (err.message or vim.inspect(err)))
            return
        end
        if result and result.success then
            Util.info("Object launched: " .. (config.startupObjectType or "") .. " " .. (config.startupObjectId or ""))
        else
            Util.error("Failed to run object")
        end
    end)
end

return run_object
