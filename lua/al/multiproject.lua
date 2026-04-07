---@class al.Multiproject.Manifest
---@field id string
---@field name string
---@field publisher string
---@field version string
---@field raw_json string          full app.json text, passed verbatim to al/loadManifest
---@field deps table[]             parsed dependency list from app.json
---@field settings table           merged alResourceConfigurationSettings

-- luacheck: ignore 211
local Config = require("al.config")
local Utils = require("al.utils")

local M = {}

--- Absolute path to the .code-workspace parent directory, or nil in single-project mode.
---@type string|nil
local _workspace_root = nil

--- Workspace object from code-workspace.nvim (has .folders, .file, .name).
---@type table|nil
local _workspace = nil

--- Manifest cache: normalised folder path → Manifest
---@type table<string, al.Multiproject.Manifest>
local _manifests = {}

--- The normalised folder path of the currently active AL project.
---@type string|nil
local _active_folder = nil

--- Debounce timer for BufEnter.
local _debounce_timer = vim.uv.new_timer()

--- Returns the workspace root directory when a multi-project workspace is active, else nil.
---@return string|nil
function M.workspace_root()
    return _workspace_root
end

return M
