local Util = require("al.utils")
local Lsp = require("al.lsp")
local Workspace = require("al.workspace")

local dependencies = function()
    local buf = vim.api.nvim_get_current_buf()
    local client = Lsp.get_client_for_buf(buf)
    if not client then
        Util.error("No AL language server attached to the current buffer.")
        return
    end

    -- Get current project name from app.json
    local fname = vim.api.nvim_buf_get_name(0)
    local ws = Workspace.find({ path = fname })
    local project_dir = require("al.multiproject").project_for_buf(buf) or (ws and ws.root)
    local name = ""
    if project_dir then
        local app_json_path = vim.fs.joinpath(project_dir, "app.json")
        local ok, app = pcall(Util.read_json_file, app_json_path)
        if ok and app then
            name = app.name or ""
        end
    end

    local params = {
        name = name,
    }

    client:request("al/getPackageDependencies", params, function(err, result)
        if err then
            Util.error("Failed to get dependencies: " .. (err.message or vim.inspect(err)))
            return
        end

        if not result or #result == 0 then
            Util.info("No package dependencies found.")
            return
        end

        local lines = { "# Package Dependencies" }
        for _, dep in ipairs(result) do
            lines[#lines + 1] = string.format(
                "- **%s** by %s (v%s) [%s]",
                dep.appName or "?",
                dep.appPublisher or "?",
                dep.appVersion or "?",
                dep.appId or "?"
            )
        end
        Util.info(lines)
    end)
end

return dependencies
