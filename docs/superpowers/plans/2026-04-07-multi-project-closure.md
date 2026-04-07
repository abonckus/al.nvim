# Multi-Project Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable the AL language server to load and resolve symbols across multiple AL projects in a workspace by implementing the `al/setActiveWorkspace` protocol with proper project-closure computation.

**Architecture:** A new `multiproject.lua` module integrates with `code-workspace.nvim`'s `WorkspaceLoaded` event to start a single AL LS instance with the workspace directory as root, loads each project's `app.json` manifest via `al/loadManifest`, and switches active project context on `BufEnter` using a debounced `al/setActiveWorkspace` request that includes the computed project-reference closure. Single-project mode (no `.code-workspace` file) is completely unaffected.

**Tech Stack:** Lua, Neovim LSP API (`vim.lsp`), nvim-nio (`nio`) for async file reads and parallel LSP requests, code-workspace.nvim for workspace folder discovery.

**Spec:** `docs/superpowers/specs/2026-04-07-multi-project-closure-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lua/al/multiproject.lua` | **Create** | All multi-project state, manifest cache, closure computation, LSP orchestration |
| `lua/al/config.lua` | Modify | Add `multiproject.settings_path` default |
| `lua/al/workspace.lua` | Modify | Fix `hasProjectClosureLoaded` global → per-folder table |
| `lua/al/buf.lua` | Modify | Guard `Workspace.set_active` call in multi-project mode |
| `lua/al/lsp.lua` | Modify | Dynamic `root_dir` based on `multiproject.workspace_root()` |

---

## Task 1: Add multiproject config key

**Files:**
- Modify: `lua/al/config.lua`

- [ ] **Step 1: Add the key to defaults**

In `lua/al/config.lua`, add a `multiproject` table inside `local defaults = { ... }`, after the `lsp` block (around line 62):

```lua
    multiproject = {
        settings_path = ".vscode/settings.json",
    },
```

The full `defaults` table tail should look like:

```lua
    lsp = {
        telemetryLevel = "all",
        browser = "SystemDefault",
        inlayHintsParameterNames = true,
        inlayHintsFunctionReturnTypes = true,
        semanticFolding = true,
        extendGoToSymbolInWorkspace = true,
        extendGoToSymbolInWorkspaceResultLimit = 100,
        extendGoToSymbolInWorkspaceIncludeSymbolFiles = true,
        log = {
            path = "",
            level = "Normal",
        },
    },
    multiproject = {
        settings_path = ".vscode/settings.json",
    },
}
```

- [ ] **Step 2: Add the type annotation**

Below the `---@class al.Config.LSP` block, add:

```lua
---@class al.Config.Multiproject
---@field settings_path string

---@class al.Config
---@field lsp al.Config.LSP
---@field multiproject al.Config.Multiproject
```

- [ ] **Step 3: Lint and format**

```bash
cd al.nvim && selene lua/ && stylua --check lua/
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lua/al/config.lua
git commit -m "feat(multiproject): add settings_path config key"
```

---

## Task 2: Fix per-folder hasProjectClosureLoaded in workspace.lua

**Files:**
- Modify: `lua/al/workspace.lua`

The current `M.hasProjectClosureLoaded = false` is a global boolean shared across all workspaces — it never resets when a second project is opened. Replace with a per-folder table.

- [ ] **Step 1: Change the initial declaration (line 13)**

```lua
-- Before:
M.hasProjectClosureLoaded = false

-- After:
M.hasProjectClosureLoaded = {} ---@type table<string, boolean>
```

- [ ] **Step 2: Fix on_set_active_response (around line 144)**

The current code:

```lua
    if not M.hasProjectClosureLoaded then
        client.request(
            client,
            "al/hasProjectClosureLoadedRequest",
            { workspacePath = ws.root },
            M.on_project_closure_loaded
        )
    end
```

Replace with an inline closure that captures `ws.root`:

```lua
    if not M.hasProjectClosureLoaded[ws.root] then
        client.request(
            client,
            "al/hasProjectClosureLoadedRequest",
            { workspacePath = ws.root },
            function(err, result)
                M.hasProjectClosureLoaded[ws.root] = result and result.loaded or false
            end
        )
    end
```

- [ ] **Step 3: Delete the now-unused on_project_closure_loaded function**

Remove lines 154-156:

```lua
function M.on_project_closure_loaded(err, result, ctx, config)
    M.hasProjectClosureLoaded = result.loaded
end
```

- [ ] **Step 4: Lint and format**

```bash
cd al.nvim && selene lua/ && stylua --check lua/
```

- [ ] **Step 5: Commit**

```bash
git add lua/al/workspace.lua
git commit -m "fix(workspace): track hasProjectClosureLoaded per folder path"
```

---

## Task 3: Guard Workspace.set_active in buf.lua

**Files:**
- Modify: `lua/al/buf.lua`

In multi-project mode, `multiproject.lua` owns `al/setActiveWorkspace`. The existing call in `buf.on_attach` must be skipped.

- [ ] **Step 1: Modify the guard in on_attach (lines 48-50)**

```lua
-- Before:
    if not Workspace.is_active(client, buf) then
        Workspace.set_active(client, buf)
    end

-- After:
    if not require("al.multiproject").workspace_root() and not Workspace.is_active(client, buf) then
        Workspace.set_active(client, buf)
    end
```

- [ ] **Step 2: Lint and format**

```bash
cd al.nvim && selene lua/ && stylua --check lua/
```

- [ ] **Step 3: Commit**

```bash
git add lua/al/buf.lua
git commit -m "feat(buf): skip set_active when multi-project workspace is active"
```

---

## Task 4: multiproject.lua — skeleton, state, and workspace_root()

**Files:**
- Create: `lua/al/multiproject.lua`

- [ ] **Step 1: Create the file with module state and workspace_root()**

```lua
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
```

- [ ] **Step 2: Lint and format**

```bash
cd al.nvim && selene lua/ && stylua --check lua/
```

Expected: no errors (file has no complex logic yet).

- [ ] **Step 3: Commit**

```bash
git add lua/al/multiproject.lua
git commit -m "feat(multiproject): add module skeleton and workspace_root()"
```

---

## Task 5: multiproject.lua — manifest loading

**Files:**
- Modify: `lua/al/multiproject.lua`

- [ ] **Step 1: Add the nio require at the top of the file**

After the `local Config = require("al.config")` line, add:

```lua
local nio = require("nio")
```

- [ ] **Step 2: Add the path normalisation helper**

After the `local _debounce_timer` line, add:

```lua
local IS_WINDOWS = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1

---@param path string
---@return string
local function norm(path)
    local n = vim.fs.normalize(path)
    return IS_WINDOWS and n:lower() or n
end
```

- [ ] **Step 3: Add the async file reader**

After the `norm` function, add:

```lua
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
```

- [ ] **Step 4: Add _load_manifests()**

After `read_file_async`, add:

```lua
--- Load and cache app.json + settings for every workspace folder.
--- Must be called inside a nio.run() task.
---@param ws table  workspace object from code-workspace.nvim
local function _load_manifests(ws)
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
                    local al_block = settings_parsed["al"] or {}
                    proj_al_settings = al_block["alResourceConfigurationSettings"] or {}
                end
            end

            -- Merge: global defaults < per-project settings
            local merged_settings =
                vim.tbl_deep_extend("force", {}, global_settings, proj_al_settings)

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
```

- [ ] **Step 5: Lint and format**

```bash
cd al.nvim && selene lua/ && stylua --check lua/
```

- [ ] **Step 6: Commit**

```bash
git add lua/al/multiproject.lua
git commit -m "feat(multiproject): async manifest loading with nio"
```

---

## Task 6: multiproject.lua — closure computation

**Files:**
- Modify: `lua/al/multiproject.lua`

- [ ] **Step 1: Add _compute_closure()**

After `_load_manifests`, add:

```lua
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
```

- [ ] **Step 2: Add _folder_for_buf()**

After `_compute_closure`, add the helper that maps a buffer to its AL project folder:

```lua
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
            return fp, folder.name, i - 1  -- index is 0-based
        end
    end
    return nil
end
```

- [ ] **Step 3: Lint and format**

```bash
cd al.nvim && selene lua/ && stylua --check lua/
```

- [ ] **Step 4: Commit**

```bash
git add lua/al/multiproject.lua
git commit -m "feat(multiproject): closure computation and folder-for-buf helpers"
```

---

## Task 7: multiproject.lua — setActiveWorkspace + dependency notifications

**Files:**
- Modify: `lua/al/multiproject.lua`

- [ ] **Step 1: Add _build_set_active_request()**

After `_folder_for_buf`, add:

```lua
--- Build the al/setActiveWorkspace request body.
---@param client vim.lsp.Client
---@param folder_norm string
---@param folder_name string
---@param folder_index integer  0-based
---@param closure_data al.Multiproject.Closure
---@return table
local function _build_set_active_request(client, folder_norm, folder_name, folder_index, closure_data)
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
```

- [ ] **Step 2: Add _send_dep_notifications()**

After `_build_set_active_request`, add:

```lua
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
```

- [ ] **Step 3: Add _switch_active_workspace()**

After `_send_dep_notifications`, add:

```lua
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
        return  -- already active, nothing to do
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
        if not (require("al.workspace").hasProjectClosureLoaded[folder_norm]) then
            client:request(
                "al/hasProjectClosureLoadedRequest",
                { workspacePath = folder_norm },
                function(herr, hresult)
                    if not herr and hresult then
                        require("al.workspace").hasProjectClosureLoaded[folder_norm] =
                            hresult.loaded
                    end
                end
            )
        end
        return vim.NIL
    end

    client:request(
        "al/setActiveWorkspace",
        _build_set_active_request(client, folder_norm, folder_name, folder_index, closure_data),
        function(err, result)
            if err or (result and not result.success) then
                Utils.warn("multiproject: al/setActiveWorkspace failed for " .. folder_norm)
                -- Restore handler if request failed before server sent activeProjectLoaded
            end
        end
    )
end
```

- [ ] **Step 4: Lint and format**

```bash
cd al.nvim && selene lua/ && stylua --check lua/
```

- [ ] **Step 5: Commit**

```bash
git add lua/al/multiproject.lua
git commit -m "feat(multiproject): setActiveWorkspace and dependency notifications"
```

---

## Task 8: multiproject.lua — LspAttach: loadManifest + hasProjectClosureLoaded

**Files:**
- Modify: `lua/al/multiproject.lua`

On every al_ls client attach in multi-project mode, send `al/loadManifest` for all workspace folders in parallel and probe closure state for each.

- [ ] **Step 1: Add _on_lsp_attach()**

After `_switch_active_workspace`, add:

```lua
--- Called when an al_ls client attaches in multi-project mode.
--- Sends al/loadManifest for all workspace folders and probes closure state.
---@param client vim.lsp.Client
local function _on_lsp_attach(client)
    if not _workspace_root or vim.tbl_isempty(_manifests) then
        return
    end

    nio.run(function()
        local Workspace = require("al.workspace")

        -- Send al/loadManifest for all folders in parallel
        local load_tasks = {}
        for folder_norm, manifest in pairs(_manifests) do
            load_tasks[#load_tasks + 1] = nio.run(function()
                local request = nio.wrap(function(cb)
                    client:request(
                        "al/loadManifest",
                        { projectFolder = folder_norm, manifest = manifest.raw_json },
                        cb
                    )
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

        -- Probe al/hasProjectClosureLoadedRequest for all folders in parallel
        local probe_tasks = {}
        for folder_norm, _ in pairs(_manifests) do
            probe_tasks[#probe_tasks + 1] = nio.run(function()
                local request = nio.wrap(function(cb)
                    client:request(
                        "al/hasProjectClosureLoadedRequest",
                        { workspacePath = folder_norm },
                        cb
                    )
                end, 1)
                local err, result = request()
                if not err and result then
                    Workspace.hasProjectClosureLoaded[folder_norm] = result.loaded
                end
            end)
        end
        for _, t in ipairs(probe_tasks) do
            t.wait()
        end
    end)
end
```

- [ ] **Step 2: Register al/projectsLoadedNotification handler**

After `_on_lsp_attach`, add a function that registers the global notification handler. This updates the per-folder closure state when the server reports projects loaded:

```lua
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
```

- [ ] **Step 3: Lint and format**

```bash
cd al.nvim && selene lua/ && stylua --check lua/
```

- [ ] **Step 4: Commit**

```bash
git add lua/al/multiproject.lua
git commit -m "feat(multiproject): send al/loadManifest and probe closure on LspAttach"
```

---

## Task 9: multiproject.lua — workspace lifecycle and BufEnter

**Files:**
- Modify: `lua/al/multiproject.lua`

- [ ] **Step 1: Add on_workspace_loaded()**

After `_register_notification_handlers`, add:

```lua
--- Handle WorkspaceLoaded from code-workspace.nvim.
---@param ws table  workspace object: { file, name, folders: [{path, name}] }
function M.on_workspace_loaded(ws)
    _workspace = ws
    _workspace_root = norm(vim.fn.fnamemodify(ws.file, ":p:h"))
    _manifests = {}
    _active_folder = nil

    -- Stop any existing al_ls clients so they restart with the new root_dir
    for _, client in ipairs(vim.lsp.get_clients({ name = "al_ls" })) do
        vim.lsp.stop_client(client.id)
    end

    -- Load all manifests asynchronously. When done, the next LspAttach
    -- (triggered by the next BufEnter on an .al file) will send loadManifest.
    nio.run(function()
        _load_manifests(ws)
    end)
end
```

- [ ] **Step 2: Add on_workspace_closed()**

After `on_workspace_loaded`, add:

```lua
--- Handle WorkspaceClosed from code-workspace.nvim.
function M.on_workspace_closed()
    _workspace_root = nil
    _workspace = nil
    _manifests = {}
    _active_folder = nil

    -- Stop al_ls clients; they will restart with per-project root_dir on next BufEnter
    for _, client in ipairs(vim.lsp.get_clients({ name = "al_ls" })) do
        vim.lsp.stop_client(client.id)
    end
end
```

- [ ] **Step 3: Add setup()**

After `on_workspace_closed`, add:

```lua
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

    -- LspAttach: in multi-project mode, send loadManifest for all folders
    vim.api.nvim_create_autocmd("LspAttach", {
        group = group,
        callback = function(ev)
            local client = vim.lsp.get_client_by_id(ev.data.client_id)
            if client and client.name == "al_ls" and _workspace_root then
                _on_lsp_attach(client)
            end
        end,
    })

    -- BufEnter: debounced active-workspace switching
    vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        pattern = "*.al",
        callback = function(ev)
            if not _workspace_root then
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
end
```

- [ ] **Step 4: Lint and format**

```bash
cd al.nvim && selene lua/ && stylua --check lua/
```

- [ ] **Step 5: Commit**

```bash
git add lua/al/multiproject.lua
git commit -m "feat(multiproject): workspace lifecycle and debounced BufEnter switching"
```

---

## Task 10: lsp.lua — dynamic root_dir

**Files:**
- Modify: `lua/al/lsp.lua`

- [ ] **Step 1: Replace the root_dir function (lines 98-105)**

Current code:

```lua
        root_dir = function(bufnr, on_dir)
            local fname = vim.api.nvim_buf_get_name(bufnr)
            local has_al_project_cfg = function(path)
                local alpath = vim.fs.joinpath(path, "app.json")
                return (vim.uv.fs_stat(alpath) or {}).type == "file"
            end
            on_dir(vim.iter(vim.fs.parents(fname)):find(has_al_project_cfg) or vim.fs.root(0, ".alpackages"))
        end,
```

Replace with:

```lua
        root_dir = function(bufnr, on_dir)
            -- In multi-project mode all AL files share one client rooted at the workspace dir
            local ws_root = require("al.multiproject").workspace_root()
            if ws_root then
                on_dir(ws_root)
                return
            end
            -- Single-project fallback: walk up to the nearest app.json parent
            local fname = vim.api.nvim_buf_get_name(bufnr)
            local has_al_project_cfg = function(path)
                local alpath = vim.fs.joinpath(path, "app.json")
                return (vim.uv.fs_stat(alpath) or {}).type == "file"
            end
            on_dir(
                vim.iter(vim.fs.parents(fname)):find(has_al_project_cfg)
                    or vim.fs.root(0, ".alpackages")
            )
        end,
```

- [ ] **Step 2: Lint and format**

```bash
cd al.nvim && selene lua/ && stylua --check lua/
```

- [ ] **Step 3: Commit**

```bash
git add lua/al/lsp.lua
git commit -m "feat(lsp): use workspace root as root_dir in multi-project mode"
```

---

## Task 11: Wire multiproject.setup() and integration smoke-test

**Files:**
- Modify: `lua/al/config.lua`

- [ ] **Step 1: Add multiproject.setup() to the vim.schedule block (around line 135)**

Current block:

```lua
    vim.schedule(function()
        require("al.lsp").setup()
        require("al.debugger").setup()
        require("al.buf").setup()
        require("al.integrations").setup()
    end)
```

Replace with:

```lua
    vim.schedule(function()
        require("al.lsp").setup()
        require("al.debugger").setup()
        require("al.buf").setup()
        require("al.integrations").setup()
        require("al.multiproject").setup()
    end)
```

- [ ] **Step 2: Lint and format**

```bash
cd al.nvim && selene lua/ && stylua --check lua/
```

- [ ] **Step 3: Commit**

```bash
git add lua/al/config.lua
git commit -m "feat(config): wire multiproject.setup() into plugin init"
```

- [ ] **Step 4: Smoke test — single-project mode (regression)**

Open any `.al` file in a repo with one `app.json` and no `.code-workspace` file loaded.

Verify in `:LspInfo`:
- One `al_ls` client attached, `root_dir` = the `app.json` parent (unchanged behaviour)

Run `:lua =require("al.multiproject").workspace_root()` → should print `nil`.

- [ ] **Step 5: Smoke test — multi-project mode**

Open a `.code-workspace` file with multiple AL project folders (or run `:Workspace open path/to/file.code-workspace`).

Verify:
```
:lua =require("al.multiproject").workspace_root()
-- should print the workspace directory path

:LspInfo
-- one al_ls client, root_dir = workspace directory
```

Open a file in project A. Wait 200ms. Run:
```
:lua =require("al.multiproject")._active_folder
-- should print project A's normalised path
```

Switch to a file in project B. Wait 200ms. Run:
```
:lua =require("al.multiproject")._active_folder
-- should print project B's normalised path
```

Check `:LspLog` for `al/setActiveWorkspace` requests and `workspace/didChangeConfiguration` notifications confirming the closure is being sent.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat(multiproject): complete multi-project closure support

Integrates with code-workspace.nvim to start a single AL LS instance
per workspace, loads app.json manifests for all folders, and switches
active project context via al/setActiveWorkspace with computed closure
on BufEnter. Single-project mode unaffected.

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** All spec sections covered: single LSP instance (Task 10), manifest loading (Task 8), closure computation (Task 6), setActiveWorkspace (Task 7), dep notifications (Task 7), per-project settings (Task 5), hasProjectClosureLoaded fix (Task 2), projectsLoadedNotification (Task 8), BufEnter debounce (Task 9).
- **`_active_folder` exposure:** Exposed as `M._active_folder` for the smoke test in Task 11. This is intentional for debuggability.
- **`al/activeProjectLoaded` handler:** Uses a one-shot approach in `_switch_active_workspace` (Task 7) so multiple concurrent project switches don't stack handlers. The existing per-client handler set in `lsp.attach()` (`return vim.NIL`) is overridden by this; when multi-project mode is off and `_switch_active_workspace` is never called, the original handler from `lsp.attach()` remains in place.
- **code-workspace.nvim optional:** If the user doesn't have code-workspace.nvim installed, the `User WorkspaceLoaded` autocmd simply never fires and the plugin stays in single-project mode. No error.
