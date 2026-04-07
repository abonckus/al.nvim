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

---@class al.Multiproject.Closure
---@field closure string[]   list of folder paths for activeWorkspaceClosure
---@field refs table[]       list of {appId,name,publisher,version} for expectedProjectReferenceDefinitions
---@field settings table     alResourceConfigurationSettings for the active folder

--- Compute the project-reference closure for the given folder.
--- Pure function — reads only from _manifests, no I/O.
---@param folder_norm string  normalised absolute path to the active AL project folder
---@return al.Multiproject.Closure
local function _compute_closure(folder_norm) -- luacheck: ignore 211
    local manifest = _manifests[folder_norm]
    if not manifest then
        return { closure = { folder_norm }, refs = {}, settings = {} }
    end

    local closure = { folder_norm }
    local refs = {}

    for _, dep in ipairs(manifest.deps) do
        for dep_path, dep_manifest in pairs(_manifests) do
            if dep_path ~= folder_norm and dep_manifest.id == dep.id then
                -- This dependency is another workspace folder → project reference
                table.insert(closure, dep_path)
                table.insert(refs, {
                    appId = dep_manifest.id,
                    name = dep_manifest.name,
                    publisher = dep_manifest.publisher,
                    version = dep_manifest.version,
                })
                break
            end
        end
    end

    return { closure = closure, refs = refs, settings = manifest.settings }
end

--- Return the normalised project folder path that contains the given buffer, or nil.
---@param bufnr integer
---@return string|nil folder_norm, string|nil folder_name, integer|nil folder_index
local function _folder_for_buf(bufnr) -- luacheck: ignore 211
    local fname = norm(vim.api.nvim_buf_get_name(bufnr))
    if fname == "" then
        return nil
    end
    -- Walk workspace folders in order so index is stable
    if not _workspace then
        return nil
    end
    for i, folder in ipairs(_workspace.folders) do
        local fp = norm(folder.path)
        if fname == fp or fname:sub(1, #fp + 1) == fp .. "/" then
            return fp, folder.name, i - 1 -- index is 0-based
        end
    end
    return nil
end

--- Build the al/setActiveWorkspace request body.
---@param folder_norm string
---@param folder_name string
---@param folder_index integer  0-based
---@param closure_data al.Multiproject.Closure
---@return table
local function _build_set_active_request(folder_norm, folder_name, folder_index, closure_data)
    return {
        currentWorkspaceFolderPath = {
            uri = {
                ["$mid"] = 1,
                fsPath = folder_norm,
                _sep = 1,
                external = vim.uri_from_fname(folder_norm),
                scheme = "file",
                path = folder_norm,
            },
            name = folder_name,
            index = folder_index,
        },
        settings = {
            workspacePath = folder_norm,
            alResourceConfigurationSettings = closure_data.settings,
            setActiveWorkspace = true,
            expectedProjectReferenceDefinitions = closure_data.refs,
            activeWorkspaceClosure = closure_data.closure,
        },
    }
end

--- Send workspace/didChangeConfiguration for every dependency folder in the closure.
--- Called inside al/activeProjectLoaded handler, before returning the ack.
---@param client vim.lsp.Client
---@param active_folder_norm string
---@param closure_data al.Multiproject.Closure
local function _send_dep_notifications(client, active_folder_norm, closure_data)
    for _, dep_path in ipairs(closure_data.closure) do
        if dep_path ~= active_folder_norm then
            local dep_manifest = _manifests[dep_path]
            if dep_manifest then
                client:notify("workspace/didChangeConfiguration", {
                    settings = {
                        workspacePath = dep_path,
                        alResourceConfigurationSettings = dep_manifest.settings,
                        setActiveWorkspace = false,
                        dependencyParentWorkspacePath = active_folder_norm,
                        expectedProjectReferenceDefinitions = {},
                        activeWorkspaceClosure = {},
                    },
                })
            end
        end
    end
end

--- Send al/setActiveWorkspace for the given folder. No-op if already active.
--- Must be called from the main thread (scheduled context).
---@param bufnr integer
local function _switch_active_workspace(bufnr) -- luacheck: ignore 211
    if not _workspace_root then
        return
    end

    local folder_norm, folder_name, folder_index = _folder_for_buf(bufnr)
    if not folder_norm then
        return
    end
    if folder_norm == _active_folder then
        return -- already active, nothing to do
    end

    local clients = vim.lsp.get_clients({ name = "al_ls" })
    if #clients == 0 then
        return
    end
    local client = clients[1]

    local closure_data = _compute_closure(folder_norm)

    -- Install a one-shot al/activeProjectLoaded handler that sends dep notifications
    -- and then restores the default nil-return handler.
    local prev_handler = client.handlers["al/activeProjectLoaded"]
    client.handlers["al/activeProjectLoaded"] = function(err, result, ctx, cfg)
        -- Send dependency folder notifications before acking
        _send_dep_notifications(client, folder_norm, closure_data)
        -- Restore previous handler
        client.handlers["al/activeProjectLoaded"] = prev_handler
        -- Update tracked active folder
        _active_folder = folder_norm
        -- Probe closure loaded state for the new active folder
        if not require("al.workspace").hasProjectClosureLoaded[folder_norm] then
            client:request("al/hasProjectClosureLoadedRequest", { workspacePath = folder_norm }, function(herr, hresult)
                if not herr and hresult then
                    require("al.workspace").hasProjectClosureLoaded[folder_norm] = hresult.loaded
                end
            end)
        end
        return vim.NIL
    end

    client:request(
        "al/setActiveWorkspace",
        _build_set_active_request(folder_norm, folder_name, folder_index, closure_data),
        function(err, result)
            if err or (result and not result.success) then
                Utils.warn("multiproject: al/setActiveWorkspace failed for " .. folder_norm)
                client.handlers["al/activeProjectLoaded"] = prev_handler
            end
        end
    )
end

--- Returns the workspace root directory when a multi-project workspace is active, else nil.
---@return string|nil
function M.workspace_root()
    return _workspace_root
end

return M
