local Config = require("al.config")
local Util = require("al.utils")
local Workspace = require("al.workspace")
local Lsp = require("al.lsp")

local build_package = function()
    local co = coroutine.running()
    local fname = vim.api.nvim_buf_get_name(0)
    local buf = vim.api.nvim_get_current_buf()
    local project_dir = require("al.multiproject").project_for_buf(buf)
    if not project_dir then
        local ws = Workspace.find({ path = fname })
        project_dir = ws and ws.root
    end
    if not project_dir then
        Util.error("Could not determine AL project directory for current buffer.")
        return
    end
    local params = {
        projectDir = project_dir,
        args = {
            "-project:" .. project_dir,
        },
        isRad = false,
        vSCodeExtensionVersion = Config.language_extension_version,
        forceBuildDependencies = false,
    }

    local client = Lsp.get_client_for_buf(buf)
    if not client then
        Util.error("No AL language server attached to the current buffer.")
        coroutine.resume(co)
        return
    end

    Util.info("Started creating package...")
    client.request(client, "al/createPackage", params, function(err, result)
        if not result then
            coroutine.resume(co)
            return
        end
        if result.success then
            Util.info("Success: The package is created")
        else
            Util.error("Failed creating AL package\r\n" .. vim.inspect(err))
        end
        coroutine.resume(co)
    end)
    return coroutine.yield()
end

return build_package
