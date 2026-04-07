---@class al.Multiproject.Manifest
---@field id string
---@field name string
---@field publisher string
---@field version string
---@field raw_json string          full app.json text, passed verbatim to al/loadManifest
---@field deps table[]             parsed dependency list from app.json
---@field settings table           merged alResourceConfigurationSettings

local Config = require("al.config")
local Utils = require("al.utils")
local nio = require("nio")

local M = {}

--- Absolute path to the .code-workspace parent directory, or nil in single-project mode.
---@type string|nil
local _workspace_root = nil

--- Workspace object from code-workspace.nvim (has .folders, .file, .name).
---@type table|nil
local _workspace = nil -- luacheck: ignore 211

--- Manifest cache: normalised folder path → Manifest
---@type table<string, al.Multiproject.Manifest>
local _manifests = {} -- luacheck: ignore 211 241

--- The normalised folder path of the currently active AL project.
---@type string|nil
local _active_folder = nil -- luacheck: ignore 211

--- Debounce timer for BufEnter.
local _debounce_timer = vim.uv.new_timer() -- luacheck: ignore 211

local IS_WINDOWS = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1

---@param path string
---@return string
local function norm(path)
    local n = vim.fs.normalize(path)
    return IS_WINDOWS and n:lower() or n
end

--- Read a file asynchronously. Returns content string or nil on error.
---@param path string
---@return string|nil
local function read_file_async(path)
    local err, fd = nio.uv.fs_open(path, "r", 438)
    if err or not fd then
        return nil
    end
    local serr, stat = nio.uv.fs_fstat(fd)
    if serr or not stat then
        nio.uv.fs_close(fd)
        return nil
    end
    local rerr, data = nio.uv.fs_read(fd, stat.size, 0)
    nio.uv.fs_close(fd)
    if rerr then
        return nil
    end
    return data
end

--- Load and cache app.json + settings for every workspace folder.
--- Must be called inside a nio.run() task.
---@param ws table  workspace object from code-workspace.nvim
local function _load_manifests(ws) -- luacheck: ignore 211
    local global_settings = (Config.workspace or {}).alResourceConfigurationSettings or {}
    local settings_path = (Config.multiproject or {}).settings_path or ".vscode/settings.json"

    local tasks = vim.tbl_map(function(folder)
        return nio.run(function()
            local folder_norm = norm(folder.path)

            -- Read app.json (required)
            local app_json_path = folder.path .. "/" .. "app.json"
            local raw_json = read_file_async(app_json_path)
            if not raw_json then
                Utils.warn("multiproject: could not read " .. app_json_path)
                return
            end

            local ok, parsed = pcall(vim.json.decode, raw_json)
            if not ok or type(parsed) ~= "table" then
                Utils.warn("multiproject: could not parse " .. app_json_path)
                return
            end

            -- Read per-project settings (optional)
            local proj_settings_path = folder.path .. "/" .. settings_path
            local proj_al_settings = {}
            local settings_raw = read_file_async(proj_settings_path)
            if settings_raw then
                local sok, settings_parsed = pcall(vim.json.decode, settings_raw)
                if sok and type(settings_parsed) == "table" then
                    proj_al_settings = settings_parsed["al.alResourceConfigurationSettings"] or {}
                end
            end

            -- Merge: global defaults < per-project settings
            local merged_settings = vim.tbl_deep_extend("force", {}, global_settings, proj_al_settings)

            _manifests[folder_norm] = {
                id = parsed.id or "",
                name = parsed.name or folder.name,
                publisher = parsed.publisher or "",
                version = parsed.version or "0.0.0.0",
                raw_json = raw_json,
                deps = parsed.dependencies or {},
                settings = merged_settings,
                folder_name = folder.name,
            }
        end)
    end, ws.folders)

    -- Wait for all folder reads to complete
    for _, task in ipairs(tasks) do
        task.wait()
    end
end

--- Returns the workspace root directory when a multi-project workspace is active, else nil.
---@return string|nil
function M.workspace_root()
    return _workspace_root
end

return M
