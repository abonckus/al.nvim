local Config = require("al.config")
local Util = require("al.utils")
local Workspace = require("al.workspace")
local Lsp = require("al.lsp")

local auth = require("al.editor_commands.auth")

---@param config al.LaunchConfiguration
local publish = function(config)
    local buf = vim.api.nvim_get_current_buf()
    local client = Lsp.get_client_for_buf(buf)
    if not client then
        Util.error("No AL language server attached to the current buffer.")
        return
    end

    -- Authenticate first
    local auth_result = auth(config)
    if auth_result ~= "success" then
        if auth_result == "cancelled" then
            Util.warn("Publish cancelled — authentication cancelled.")
        else
            Util.error("Publish failed — authentication failed.")
        end
        return
    end

    -- Resolve project directory
    local project_dir = require("al.multiproject").project_for_buf(buf)
    if not project_dir then
        local fname = vim.api.nvim_buf_get_name(0)
        local ws = Workspace.find({ path = fname })
        project_dir = ws and ws.root
    end
    if not project_dir then
        Util.error("Could not determine AL project directory.")
        return
    end

    local params = {
        configuration = config,
        projectDir = project_dir,
        args = {
            "-project:" .. project_dir,
        },
        vSCodeExtensionVersion = Config.language_extension_version,
    }

    Util.info("Publishing package...")
    client:request("al/fullDependencyPublish", params, function(err, result)
        if err then
            Util.error("Publish failed: " .. (err.message or vim.inspect(err)))
            return
        end
        if result and result.success then
            Util.info("Package published successfully")
        else
            Util.error("Publish failed")
        end
    end)

    return coroutine.yield()
end

return publish
