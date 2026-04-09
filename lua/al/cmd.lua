local Lsp = require("al.lsp")
local Workspace = require("al.workspace")
local Util = require("al.utils")
local Config = require("al.config")
local State = require("al.state")

local M = {}

--- Helper: find the AL project root for the current buffer.
---@return string|nil
local function get_project_root()
    local buf = vim.api.nvim_get_current_buf()
    -- Multi-project mode first
    local mp_ok, mp = pcall(require, "al.multiproject")
    if mp_ok then
        local dir = mp.project_for_buf(buf)
        if dir then
            return dir
        end
    end
    -- Workspace registry
    local fname = vim.api.nvim_buf_get_name(buf)
    local ws = Workspace.find({ path = fname })
    if ws then
        return ws.root
    end
    -- Walk up to find app.json (works before LSP has initialized)
    local root = vim.fs.root(buf, "app.json")
    return root
end

--- Helper: read launch.json configs for current buffer's workspace.
---@return al.LaunchConfiguration[]
local function get_launch_configurations()
    local root = get_project_root()
    if not root then
        Util.error("Could not determine AL workspace.")
        return {}
    end
    local ok, configs = pcall(Util.read_json_file, vim.fs.joinpath(root, ".vscode/launch.json"))
    if not ok or not configs then
        Util.error("Could not read launch.json")
        return {}
    end
    return configs.configurations or {}
end

--- Helper: wrap a config-dependent command in coroutine with config resolution.
---@param fn fun(config: al.LaunchConfiguration)
local function with_config(fn)
    -- Always wrap in coroutine — commands like authenticate/publish yield internally
    coroutine.resume(coroutine.create(function()
        local config
        if State.active_config then
            config = State.active_config
        else
            local configs = get_launch_configurations()
            if #configs == 0 then
                return
            end
            config = State.resolve_config(configs)
        end
        if config then
            fn(vim.tbl_extend("force", Config.default_launch_cfg, config))
        end
    end))
end

M.commands = {
    config = function(args)
        require("al.editor_commands.config")(args, get_launch_configurations())
    end,
    lsp = function()
        local clients = Util.get_clients({ bufnr = 0 })
        clients = vim.tbl_filter(function(client)
            return client and Lsp.supports(client)
        end, clients)
        local lines = {}
        for _, client in ipairs(clients) do
            lines[#lines + 1] = "## " .. client.name
            lines[#lines + 1] = "```lua"
            lines[#lines + 1] = "settings = " .. vim.inspect(client.settings)
            lines[#lines + 1] = "```"
        end
        Util.info(lines)
    end,
    build = function()
        coroutine.resume(coroutine.create(function()
            require("al.editor_commands.build")()
        end))
    end,
    publish = function()
        with_config(function(config)
            require("al.editor_commands.publish")(config)
        end)
    end,
    downloadSymbols = function()
        with_config(function(config)
            require("al.editor_commands.download_symbols")(config)
        end)
    end,
    refreshSymbols = function()
        require("al.editor_commands.refresh_symbols")()
    end,
    downloadSource = function()
        require("al.editor_commands.download_source")()
    end,
    authenticate = function()
        with_config(function(config)
            local auth = require("al.editor_commands.auth")
            local result = auth(config)
            if result == "success" then
                Util.info("Authentication successful for " .. config.name)
            elseif result == "fail" then
                Util.error("Authentication failed for " .. config.name)
            elseif result == "cancelled" then
                Util.warn("Authentication cancelled for " .. config.name)
            end
        end)
    end,
    clearCredentialsCache = function()
        with_config(function(config)
            require("al.editor_commands.clear_credential_cache")(config)
        end)
    end,
    definition = function()
        Lsp.go_to_definition()
    end,
    runObject = function(args)
        with_config(function(config)
            require("al.editor_commands.run_object")(config, args)
        end)
    end,
    openInBrowser = function()
        with_config(function(config)
            require("al.editor_commands.open_in_browser")(config)
        end)
    end,
    restartLsp = function()
        require("al.editor_commands.restart_lsp")()
    end,
    eventPublishers = function()
        require("al.editor_commands.event_publishers")()
    end,
    symbolSearch = function(args)
        require("al.editor_commands.symbol_search")(args)
    end,
    dependencies = function()
        require("al.editor_commands.dependencies")()
    end,
    generatePermissionSet = function()
        require("al.editor_commands.generate_permission_set")()
    end,
}

function M.execute(input)
    local prefix, args = M.parse(input.args)
    if not prefix or prefix == "" then
        Util.error("Usage: :AL <command>. Available: " .. table.concat(vim.tbl_keys(M.commands), ", "))
        return
    end
    if not M.commands[prefix] then
        Util.error("Unknown command: " .. prefix .. ". Available: " .. table.concat(vim.tbl_keys(M.commands), ", "))
        return
    end
    M.commands[prefix](args)
end

function M.complete(_, line)
    local prefix, args = M.parse(line)
    if #args > 0 then
        return {}
    end

    return vim.tbl_filter(function(key)
        return key:find(prefix, 1, true) == 1
    end, vim.tbl_keys(M.commands))
end

---@return string, string[]
function M.parse(args)
    local parts = vim.split(vim.trim(args), "%s+")
    if parts[1]:find("AL") then
        table.remove(parts, 1)
    end
    if args:sub(-1) == " " then
        parts[#parts + 1] = ""
    end
    return table.remove(parts, 1) or "", parts
end

return M
