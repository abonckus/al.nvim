---@class al.Multiproject.Manifest
---@field id string
---@field name string
---@field publisher string
---@field version string
---@field raw_json string          full app.json text, passed verbatim to al/loadManifest
---@field deps table[]             parsed dependency list from app.json
---@field settings table           merged alResourceConfigurationSettings
---@field folder_path string       original-case path from code-workspace.nvim (for server comms)

local Config = require("al.config")
local Utils = require("al.utils")
local nio = require("nio")

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

--- True once _on_lsp_attach has finished sending al/loadManifest to the server.
--- BufEnter's debounced _switch_active_workspace is gated on this flag to prevent
--- sending setActiveWorkspace before the server has all manifest metadata.
local _manifests_sent = false

local IS_WINDOWS = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1

---@param path string
---@return string
local function norm(path)
    local n = vim.fs.normalize(path)
    return IS_WINDOWS and n:lower() or n
end

--- Convert a path to the format the AL Language Server expects:
--- original case, backslashes on Windows.
---@param path string
---@return string
local function to_server_path(path)
    local n = vim.fs.normalize(path)
    if IS_WINDOWS then
        return (n:gsub("/", "\\"))
    end
    return n
end

--- Look up the server-format path for a normalised folder key.
--- Uses the original-case path stored in the manifest, falling back
--- to converting the normalised key (which loses case on Windows).
---@param folder_norm string
---@return string
local function server_path_for(folder_norm)
    local m = _manifests[folder_norm]
    if m and m.folder_path then
        return to_server_path(m.folder_path)
    end
    return to_server_path(folder_norm)
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
local function _load_manifests(ws)
    local global_settings = (Config.workspace or {}).alResourceConfigurationSettings or {}
    local settings_path = (Config.multiproject or {}).settings_path or ".vscode/settings.json"

    local tasks = vim.tbl_map(function(folder)
        return nio.run(function()
            local folder_norm = norm(folder.path)

            -- Read app.json — skip silently if missing (non-AL workspace folders
            -- such as .claude/ are normal and expected in a .code-workspace file)
            local app_json_path = folder.path .. "/" .. "app.json"
            local raw_json = read_file_async(app_json_path)
            if not raw_json then
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
                folder_path = folder.path, -- original-case path from code-workspace.nvim
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
local function _compute_closure(folder_norm)
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
local function _folder_for_buf(bufnr)
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
--- All paths sent to the server use original-case backslash format (matching VS Code).
---@param folder_norm string
---@param folder_name string
---@param folder_index integer  0-based
---@param closure_data al.Multiproject.Closure
---@return table
local function _build_set_active_request(folder_norm, folder_name, folder_index, closure_data)
    local sp = server_path_for(folder_norm)
    local manifest = _manifests[folder_norm]
    local original = manifest and manifest.folder_path or folder_norm
    -- uri.path uses forward slashes with leading / (VS Code format)
    local uri_path = "/" .. vim.fs.normalize(original):gsub("^/", "")

    return {
        currentWorkspaceFolderPath = {
            uri = {
                ["$mid"] = 1,
                fsPath = sp,
                _sep = 1,
                external = vim.uri_from_fname(original),
                scheme = "file",
                path = uri_path,
            },
            name = folder_name,
            index = folder_index,
        },
        settings = {
            workspacePath = sp,
            alResourceConfigurationSettings = closure_data.settings,
            setActiveWorkspace = true,
            expectedProjectReferenceDefinitions = closure_data.refs,
            activeWorkspaceClosure = vim.tbl_map(server_path_for, closure_data.closure),
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
                        workspacePath = server_path_for(dep_path),
                        alResourceConfigurationSettings = dep_manifest.settings,
                        setActiveWorkspace = false,
                        dependencyParentWorkspacePath = server_path_for(active_folder_norm),
                        expectedProjectReferenceDefinitions = {},
                        activeWorkspaceClosure = {},
                    },
                })
            end
        end
    end
end

--- Poll al/hasProjectClosureLoadedRequest for each folder in the closure and
--- emit LspProgress. Called lazily after al/setActiveWorkspace so closures load
--- only when the user first opens a file in a project, not all at startup.
---@param client vim.lsp.Client
---@param closure_data al.Multiproject.Closure
local function _poll_closure_loaded(client, closure_data)
    local Workspace = require("al.workspace")
    local timeout_ms = (Config.multiproject or {}).closure_timeout_ms or 300000
    local folders = closure_data.closure
    local total = #folders
    if total == 0 then
        return
    end
    local loaded_count = 0
    local progress_token = "al_multiproject_closure_" .. client.id

    vim.schedule(function()
        vim.api.nvim_exec_autocmds("LspProgress", {
            pattern = "begin",
            modeline = false,
            data = {
                client_id = client.id,
                params = {
                    token = progress_token,
                    value = {
                        kind = "begin",
                        title = "AL loading",
                        message = ("Loading project closure (0/%d)"):format(total),
                        percentage = 0,
                        cancellable = false,
                    },
                },
            },
        })
    end)

    local tasks = {}
    for _, folder_path in ipairs(folders) do
        tasks[#tasks + 1] = nio.run(function()
            local sp = server_path_for(folder_path)
            local request = nio.wrap(function(cb)
                vim.schedule(function()
                    client:request(
                        "al/hasProjectClosureLoadedRequest",
                        { workspacePath = sp },
                        cb
                    )
                end)
            end, 1)
            local deadline = vim.uv.now() + timeout_ms
            -- Always poll the server directly — do NOT use Workspace.hasProjectClosureLoaded
            -- as an early-out, because al/projectsLoadedNotification often fires before this
            -- loop starts and would cause it to exit instantly (no progress visible).
            while true do
                if vim.uv.now() >= deadline then
                    Utils.warn("multiproject: closure load timed out for " .. folder_path)
                    Workspace.hasProjectClosureLoaded[folder_path] = true
                    break
                end
                local err, result = request()
                if not err and type(result) == "table" and result.loaded then
                    Workspace.hasProjectClosureLoaded[folder_path] = true
                    break
                end
                nio.sleep(500)
            end
            loaded_count = loaded_count + 1
            local lc = loaded_count
            local manifest = _manifests[folder_path]
            local name = manifest and manifest.folder_name or folder_path
            vim.schedule(function()
                local is_done = lc >= total
                vim.api.nvim_exec_autocmds("LspProgress", {
                    pattern = is_done and "end" or "report",
                    modeline = false,
                    data = {
                        client_id = client.id,
                        params = {
                            token = progress_token,
                            value = {
                                kind = is_done and "end" or "report",
                                title = "AL loading",
                                message = is_done and "Project closure loaded"
                                    or ("Loading project closure (%d/%d) — %s done"):format(
                                        lc,
                                        total,
                                        name
                                    ),
                                percentage = math.floor(lc / total * 100),
                                cancellable = false,
                            },
                        },
                    },
                })
                if is_done then
                    -- Give the server's own progress notifications time to complete
                    -- naturally (they may arrive shortly after the closure is confirmed
                    -- loaded). Only dismiss stuck ones after a grace period.
                    local Lsp = require("al.lsp")
                    vim.defer_fn(function()
                        for token in pairs(Lsp._open_progress_tokens) do
                            vim.api.nvim_exec_autocmds("LspProgress", {
                                pattern = "end",
                                modeline = false,
                                data = {
                                    client_id = client.id,
                                    params = { token = token, value = { kind = "end" } },
                                },
                            })
                        end
                        Lsp._open_progress_tokens = {}
                    end, 30000)
                    -- Nudge the server to re-analyse open AL buffers now that the
                    -- closure is ready. The initial textDocument/didOpen happened before
                    -- the closure loaded, so the server returned empty diagnostics.
                    -- A didSave notification triggers re-analysis + fresh diagnostics.
                    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "al" then
                            local uri = vim.uri_from_bufnr(buf)
                            client:notify("textDocument/didSave", {
                                textDocument = { uri = uri },
                            })
                            pcall(vim.lsp.inlay_hint.enable, true, { bufnr = buf })
                        end
                    end
                end
            end)
        end)
    end
    for _, t in ipairs(tasks) do
        t.wait()
    end
end

--- Send al/setActiveWorkspace for the given folder. No-op if already active.
--- Must be called from the main thread (scheduled context).
---@param bufnr integer
local function _switch_active_workspace(bufnr)
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
        M._active_folder = folder_norm
        -- Chain to the global handler so other plugins (e.g. neotest-al) can
        -- react to al/activeProjectLoaded. Per-client handlers shadow global ones,
        -- so without this chain neotest-al's discovery trigger never fires.
        local global = vim.lsp.handlers["al/activeProjectLoaded"]
        if global then
            global(err, result, ctx, cfg)
        end
        -- Lazily poll closure loading for this project's closure.
        -- Only the active project + its deps are loaded — never all projects at once.
        nio.run(function()
            _poll_closure_loaded(client, closure_data)
        end)
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

--- Called when an al_ls client attaches in multi-project mode.
--- Sends al/loadManifest for all workspace folders so the server has project
--- metadata. Closure loading is lazy — triggered only when the user opens a
--- file in a project (via al/setActiveWorkspace on BufEnter).
---@param client vim.lsp.Client
local function _on_lsp_attach(client)
    if not _workspace_root or vim.tbl_isempty(_manifests) then
        return
    end

    nio.run(function()
        -- vim.schedule is required inside nio.wrap: client:request calls nvim API
        -- functions forbidden in fast-event (libuv callback) context (E5560).
        local load_tasks = {}
        for folder_norm, manifest in pairs(_manifests) do
            load_tasks[#load_tasks + 1] = nio.run(function()
                local request = nio.wrap(function(cb)
                    vim.schedule(function()
                        client:request("al/loadManifest", {
                            projectFolder = server_path_for(folder_norm),
                            manifest = manifest.raw_json,
                        }, cb)
                    end)
                end, 1)
                local err, result = request()
                if err or (result and not result.success) then
                    Utils.warn("multiproject: al/loadManifest failed for " .. folder_norm)
                end
            end)
        end
        for _, t in ipairs(load_tasks) do
            t.wait()
        end
        _manifests_sent = true

        -- Switch to the user's actual target buffer. The AL server receives the
        -- full closure (target + its deps) and handles loading order itself —
        -- rootPath already points to the root project (via lsp_root_dir()), so
        -- the server knows which project is the root.
        vim.schedule(function()
            _active_folder = nil
            M._active_folder = nil
            -- Find an open AL buffer to switch workspace for.
            -- The current buffer might be the dashboard/startup screen.
            local target
            local cur = vim.api.nvim_get_current_buf()
            if vim.api.nvim_buf_is_loaded(cur) and vim.bo[cur].filetype == "al" then
                target = cur
            else
                for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "al" then
                        target = buf
                        break
                    end
                end
            end
            if target then
                _switch_active_workspace(target)
            end
        end)
    end)
end

--- Register global LSP notification handlers for multi-project mode.
--- Safe to call multiple times — chains to any existing handler.
local function _register_notification_handlers()
    local prev = vim.lsp.handlers["al/projectsLoadedNotification"]
    vim.lsp.handlers["al/projectsLoadedNotification"] = function(err, result, ctx, config)
        if result and type(result.projects) == "table" then
            local Workspace = require("al.workspace")
            for _, project_path in ipairs(result.projects) do
                local pnorm = norm(project_path)
                Workspace.hasProjectClosureLoaded[pnorm] = true
            end
        end
        if prev then
            prev(err, result, ctx, config)
        end
    end
end

--- The currently active project folder (exposed for testing).
---@type string|nil
M._active_folder = nil

--- Returns the workspace root directory when a multi-project workspace is active, else nil.
---@return string|nil
function M.workspace_root()
    return _workspace_root
end

--- Returns the root directory for the AL LS client in multi-project mode.
--- Uses the first AL project folder (with app.json) instead of the workspace
--- parent directory, because the AL server expects rootPath/rootUri to point
--- to a valid AL project — matching VS Code behaviour.
--- Returns the original-case path so rootUri in the initialize request matches
--- what the server expects (not the lowercased norm() output).
---@return string|nil
function M.lsp_root_dir()
    if not _workspace_root or not _workspace then
        return nil
    end
    for _, folder in ipairs(_workspace.folders) do
        local app_json = folder.path .. "/app.json"
        if (vim.uv.fs_stat(app_json) or {}).type == "file" then
            return folder.path
        end
    end
    return nil
end

--- Returns the AL project folder for the given buffer when in multi-project mode, else nil.
--- Use this instead of Workspace.root when building/running per-project commands.
---@param bufnr integer
---@return string|nil
function M.project_for_buf(bufnr)
    if not _workspace_root then
        return nil
    end
    local folder_norm = (_folder_for_buf(bufnr))
    return folder_norm
end

--- Handle WorkspaceLoaded from code-workspace.nvim.
---@param ws table  workspace object: { file, name, folders: [{path, name}] }
function M.on_workspace_loaded(ws)
    _workspace = ws
    _workspace_root = norm(vim.fn.fnamemodify(ws.file, ":p:h"))
    _manifests = {}
    _manifests_sent = false
    _active_folder = nil
    M._active_folder = nil

    -- Stop any existing per-project al_ls clients (started before WorkspaceLoaded
    -- fired, when workspace_root() was still nil and root_dir fell back to a
    -- per-project path). After stopping, re-trigger FileType autocmds on all open
    -- AL buffers so they start a new client with the correct workspace root_dir.
    local had_clients = #vim.lsp.get_clients({ name = "al_ls" }) > 0
    for _, client in ipairs(vim.lsp.get_clients({ name = "al_ls" })) do
        vim.lsp.stop_client(client.id)
    end
    if had_clients then
        -- Defer until the stopped clients have detached from their buffers,
        -- then re-trigger FileType so vim.lsp.enable restarts with the new root_dir.
        vim.defer_fn(function()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "al" then
                    vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
                end
            end
        end, 500)
    end

    -- Load all manifests asynchronously. When done, the next LspAttach
    -- (triggered by the next BufEnter on an .al file) will send loadManifest.
    nio.run(function()
        _load_manifests(ws)
        -- If an al_ls client attached while manifests were loading, send loadManifest now
        for _, client in ipairs(vim.lsp.get_clients({ name = "al_ls" })) do
            _on_lsp_attach(client)
        end
    end)
end

--- Handle WorkspaceClosed from code-workspace.nvim.
function M.on_workspace_closed()
    _debounce_timer:stop()
    _workspace_root = nil
    _workspace = nil
    _manifests = {}
    _manifests_sent = false
    _active_folder = nil
    M._active_folder = nil

    -- Stop al_ls clients; they will restart with per-project root_dir on next BufEnter
    for _, client in ipairs(vim.lsp.get_clients({ name = "al_ls" })) do
        vim.lsp.stop_client(client.id)
    end
end

--- Register all autocmds. Called once from al.config.setup().
function M.setup()
    _register_notification_handlers()

    local group = vim.api.nvim_create_augroup("al_multiproject", { clear = true })

    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "WorkspaceLoaded",
        callback = function(ev)
            M.on_workspace_loaded(ev.data)
        end,
    })

    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "WorkspaceClosed",
        callback = function()
            M.on_workspace_closed()
        end,
    })

    -- LspAttach: send al/loadManifest for all folders, then trigger workspace
    -- switch for the current buffer AFTER all responses arrive (so the server
    -- has every project's manifest before it receives al/setActiveWorkspace).
    vim.api.nvim_create_autocmd("LspAttach", {
        group = group,
        callback = function(ev)
            local client = vim.lsp.get_client_by_id(ev.data.client_id)
            if client and client.name == "al_ls" and _workspace_root then
                _on_lsp_attach(client)
            end
        end,
    })

    -- BufEnter: debounced active-workspace switching.
    -- Gated on _manifests_sent so we never send setActiveWorkspace before the
    -- server has all project manifests (the authoritative switch comes from
    -- _on_lsp_attach after loadManifest completes).
    vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        pattern = "*.al",
        callback = function(ev)
            if not _workspace_root or not _manifests_sent then
                return
            end
            local bufnr = ev.buf
            _debounce_timer:stop()
            _debounce_timer:start(
                100,
                0,
                vim.schedule_wrap(function()
                    _switch_active_workspace(bufnr)
                end)
            )
        end,
    })

    -- code-workspace.nvim fires WorkspaceLoaded during VimEnter, which runs
    -- before this setup() call (deferred via vim.schedule in config.setup).
    -- If a workspace was already loaded before we registered the autocmd above,
    -- handle it now so workspace_root() is set before any LSP clients start.
    local ok, cws = pcall(require, "code-workspace")
    if ok and cws.active then
        local active = cws.active()
        if active then
            M.on_workspace_loaded(active)
        end
    end
end

return M
