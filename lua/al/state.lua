local M = {}

---@class al.State
---@field active_config al.LaunchConfiguration|nil
---@field active_config_name string|nil

---@type al.LaunchConfiguration|nil
M.active_config = nil

---@type string|nil
M.active_config_name = nil

--- Set the active launch configuration.
---@param config al.LaunchConfiguration
function M.set_config(config)
    M.active_config = config
    M.active_config_name = config.name
end

--- Clear the active config (e.g. on workspace change).
function M.clear_config()
    M.active_config = nil
    M.active_config_name = nil
end

--- Resolve a launch configuration: returns active config if set,
--- otherwise prompts with vim.ui.select and sets state as side effect.
--- Must be called from a coroutine — yields until user picks.
---@param configs al.LaunchConfiguration[]
---@return al.LaunchConfiguration|nil
function M.resolve_config(configs)
    if M.active_config then
        return M.active_config
    end

    local co = coroutine.running()
    assert(co, "resolve_config must be called from a coroutine")

    vim.ui.select(configs, {
        prompt = "Select launch configuration:",
        format_item = function(item)
            return item.name
        end,
    }, function(choice)
        if choice then
            M.set_config(choice)
        end
        coroutine.resume(co, choice)
    end)

    return coroutine.yield()
end

--- Return statusline data. Safe for frequent calls (all cheap lookups).
---@return { config: string|nil, lsp: boolean, closure_loaded: boolean, project: string|nil }
function M.statusline()
    local buf = vim.api.nvim_get_current_buf()
    local lsp_attached = #vim.lsp.get_clients({ name = "al_ls", bufnr = buf }) > 0

    local project = nil
    local closure_loaded = false

    local mp_ok, mp = pcall(require, "al.multiproject")
    if mp_ok and mp.workspace_root() then
        local folder = mp.project_for_buf(buf)
        if folder then
            project = vim.fn.fnamemodify(folder, ":t")
            local Workspace = require("al.workspace")
            closure_loaded = Workspace.hasProjectClosureLoaded[folder] or false
        end
    else
        -- Single project: check closure loaded for workspace root
        if lsp_attached then
            local Workspace = require("al.workspace")
            local ws = Workspace.find({ buf = buf })
            closure_loaded = ws and Workspace.hasProjectClosureLoaded[ws.root] or false
        end
    end

    return {
        config = M.active_config_name,
        lsp = lsp_attached,
        closure_loaded = closure_loaded,
        project = project,
    }
end

return M
