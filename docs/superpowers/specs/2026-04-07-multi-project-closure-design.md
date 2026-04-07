# Multi-Project Closure Support for al.nvim

**Date:** 2026-04-07  
**Status:** Approved

## Background

The AL language server (AL LS) supports multi-project workspaces where one project depends on another
via project references (not just `.alpackages` symbol files). In VS Code this is driven by a
`.code-workspace` file listing all project folders; the AL LS starts as a single instance knowing all
folders and uses `al/setActiveWorkspace` with a computed closure to provide cross-project intelligence.

Currently al.nvim starts one AL LS client per `app.json` project root. Each client is isolated — no
cross-project symbol resolution, and `activeWorkspaceClosure` is always just the one project.

## Goal

Support multi-project closure so that, for example, a Test project that references Cloud via a project
reference gets full symbol resolution into Cloud's internals — exactly as VS Code provides.

## Scope

- Multi-project mode activated by `code-workspace.nvim` loading a `.code-workspace` file
- Single-project mode (no workspace file) continues to work exactly as today — no regressions
- Per-project settings sourced from each folder's `.vscode/settings.json` (configurable path)
- Async startup using `nvim-nio`

## Architecture

### Key constraint

Multi-project closure requires **one AL LS client instance** that knows all workspace folders from
startup. Multiple per-project clients cannot resolve cross-project symbols. This drives the core
design decision: `root_dir` must return the workspace directory (not the `app.json` parent) when a
multi-project workspace is active.

### New module: `lua/al/multiproject.lua`

Owns all multi-project logic. Sits between `code-workspace.nvim` events and the existing
`workspace.lua` + `lsp.lua` machinery. Single responsibility: manage the workspace-level state and
orchestrate the AL-specific LSP protocol for multi-project mode.

### Data flow

```
WorkspaceLoaded (User autocmd from code-workspace.nvim)
    └─► multiproject.on_workspace_loaded(ws)
            ├─ stop existing al_ls clients
            ├─ for each folder (nio parallel): read app.json + settings_path
            ├─ for each folder: al/loadManifest
            └─ for each folder: al/hasProjectClosureLoadedRequest

BufEnter (debounced 100ms, al filetype only)
    └─► multiproject.on_buf_enter(bufnr)
            ├─ resolve active folder from buffer path
            ├─ compute closure from cached manifests (pure, no I/O)
            ├─ workspace.set_active(client, buf)  [with correct closure + refs]
            └─ workspace/didChangeConfiguration for each dependency folder

WorkspaceClosed (User autocmd)
    └─► multiproject.on_workspace_closed()
            └─ stop al_ls clients → revert to per-project root_dir on next BufEnter
```

### Manifest cache

`multiproject` maintains an in-memory cache keyed by normalised folder path, populated at workspace
load time:

```lua
-- M._manifests["/abs/path/to/FolderName"] = {
--   id        = "f4b69b55-...",
--   name      = "Continia Document Output",
--   publisher = "Continia Software",
--   version   = "28.1.0.0",
--   raw_json  = "{ ... }",          -- full app.json text, passed to al/loadManifest
--   deps      = { { id, name, publisher, version }, ... },
--   settings  = { alResourceConfigurationSettings = { ... } },  -- merged global + per-folder
-- }
```

### Closure computation

Pure function over the cache — no I/O:

1. Start with `active_folder`
2. Walk `_manifests[active_folder].deps`
3. For each dep whose `id` matches another cached folder's `id`:
   - Add that folder path to `activeWorkspaceClosure`
   - Add `{ id, name, publisher, version }` to `expectedProjectReferenceDefinitions`
4. Non-workspace deps are ignored (resolved from `.alpackages`)

Result feeds directly into `al/setActiveWorkspace` and `workspace/didChangeConfiguration`.

## Module Changes

### `lua/al/multiproject.lua` (new)

Public API:
- `multiproject.setup()` — register `WorkspaceLoaded` / `WorkspaceClosed` autocmds and debounced
  `BufEnter`
- `multiproject.workspace_root() → string|nil` — returns active workspace directory, or nil in
  single-project mode; consumed by `lsp.lua`
- `multiproject.on_workspace_loaded(ws)` — async entry point (nio task)
- `multiproject.on_workspace_closed()`
- `multiproject.on_buf_enter(bufnr)` — debounced, switches active workspace

### `lua/al/lsp.lua` — `root_dir` extension

```lua
root_dir = function(bufnr, on_dir)
    local ws_root = require("al.multiproject").workspace_root()
    if ws_root then
        on_dir(ws_root)
        return
    end
    -- existing per-project logic unchanged
    local fname = vim.api.nvim_buf_get_name(bufnr)
    on_dir(vim.iter(vim.fs.parents(fname)):find(has_al_project_cfg)
        or vim.fs.root(0, ".alpackages"))
end
```

No other changes to `lsp.lua`.

### `lua/al/workspace.lua` — two fixes

1. `hasProjectClosureLoaded` changes from a global boolean to a table keyed by folder path:
   ```lua
   M.hasProjectClosureLoaded = {}  -- [folder_path] = boolean
   ```
   All read/write sites updated accordingly.

2. `set_active` receives pre-computed `closure` and `refs` arguments from `multiproject` rather than
   hardcoding empty values. Signature extended:
   ```lua
   M.set_active = function(client, buf, opts)
       -- opts = { closure?: string[], refs?: table[], settings?: table }
   ```
   Defaults preserve current single-project behaviour when opts is nil.

### `lua/al/config.lua` — new key

```lua
multiproject = {
    settings_path = ".vscode/settings.json",
}
```

Settings merge order (last wins): global `Config.workspace.alResourceConfigurationSettings` →
per-folder `.vscode/settings.json` `al.alResourceConfigurationSettings`.

## Protocol Details

### `al/loadManifest`

Sent once per folder at workspace load, after reading `app.json`:
```json
{ "projectFolder": "<abs path>", "manifest": "<app.json text>" }
```
Fired in parallel (nio) for all folders. Response is awaited but only checked for `success`.

### `al/hasProjectClosureLoadedRequest`

Sent once per folder at workspace load, and again after each `al/setActiveWorkspace`. Polled
asynchronously (nio, 500ms interval, 30s timeout) until `{ "loaded": true }`. Per-folder state
stored in `workspace.hasProjectClosureLoaded[path]`.

### `al/setActiveWorkspace`

Sent on debounced `BufEnter` when the active folder changes. Payload mirrors the VS Code log:
- `currentWorkspaceFolderPath` — full URI object for the active folder
- `settings.workspacePath` — active folder path
- `settings.setActiveWorkspace` = true
- `settings.alResourceConfigurationSettings` — per-folder merged settings
- `settings.expectedProjectReferenceDefinitions` — computed from closure
- `settings.activeWorkspaceClosure` — [active folder] + dependency folder paths

### `workspace/didChangeConfiguration`

Sent after `al/activeProjectLoaded` is acknowledged, once per dependency folder in the closure:
- `settings.workspacePath` — dependency folder path
- `settings.setActiveWorkspace` = false
- `settings.dependencyParentWorkspacePath` — active folder path
- `settings.expectedProjectReferenceDefinitions` = []
- `settings.activeWorkspaceClosure` = []

## Async Strategy (nvim-nio)

`multiproject.on_workspace_loaded` runs entirely inside a `nio.run()` task:

```lua
nio.run(function()
    -- parallel reads
    local tasks = vim.tbl_map(function(folder)
        return nio.wrap(read_folder_async, 1)(folder)
    end, ws.folders)
    local manifests = nio.gather(tasks)

    -- populate cache
    -- ...

    -- parallel LSP requests
    local lsp_tasks = vim.tbl_map(function(folder)
        return nio.wrap(send_load_manifest, 2)(client, folder)
    end, ws.folders)
    nio.gather(lsp_tasks)
end)
```

Debounced `BufEnter` uses `nio.control.event` to cancel any in-flight debounce timer on rapid
navigation.

## Error Handling

- Missing `app.json` in a workspace folder: log warning, skip that folder (don't abort workspace load)
- Missing `.vscode/settings.json`: silently skip, use global settings only
- `al/loadManifest` failure: log warning per folder, continue
- `al/hasProjectClosureLoadedRequest` timeout: log warning, mark as loaded to unblock the queue
- `al/setActiveWorkspace` failure: log error, leave active workspace unchanged

## Out of Scope

- Automatic discovery of multi-project workspaces without a `.code-workspace` file
- Build commands targeting multiple projects (separate feature)
- `al/setActiveWorkspace` for non-workspace-folder buffers (e.g. `.alpackages` symbol files) — these
  continue to use the current active project
