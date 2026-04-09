local Util = require("al.utils")
local Lsp = require("al.lsp")
local Workspace = require("al.workspace")

local refresh_symbols = function()
    local buf = vim.api.nvim_get_current_buf()
    local client = Lsp.get_client_for_buf(buf)
    if not client then
        Util.error("No AL language server attached to the current buffer.")
        return
    end

    local fname = vim.api.nvim_buf_get_name(0)
    local ws = Workspace.find({ path = fname })
    local project_dir = require("al.multiproject").project_for_buf(buf) or (ws and ws.root)
    if not project_dir then
        Util.error("Could not determine AL project directory.")
        return
    end

    local alpackages = vim.fs.joinpath(project_dir, ".alpackages")

    local params = {
        appPath = alpackages,
        folders = { project_dir },
    }

    Util.info("Refreshing symbol references...")
    client:request("al/refreshSymbolReferencesRequest", params, function(err, result)
        if err then
            Util.error("Refresh symbols failed: " .. (err.message or vim.inspect(err)))
            return
        end
        Util.info("Symbol references refreshed.")
    end)
end

return refresh_symbols
