# al.nvim

Full AL language support for Neovim — LSP, debugging, build commands, and
multi-project workspaces for Microsoft Dynamics 365 Business Central.

## Features

- **LSP integration** — code completion, diagnostics, go-to-definition, inlay
  hints, and semantic folding via the AL Language Server (from the VS Code AL
  extension)
- **Multi-project workspaces** — open `.code-workspace` files containing
  multiple AL projects with full project-reference closure support (requires
  [code-workspace.nvim])
- **Debugging** — nvim-dap adapter with a cross-platform Go proxy that solves
  stdio handle issues with AL EditorServices
- **Build system** — `:AL build`, `:AL downloadSymbols`, `:AL definition`
- **Treesitter** — syntax highlighting via [tree-sitter-al]
- **Snippets** — AL snippets via LuaSnip
- **Progress notifications** — real-time feedback during project loading and
  builds

## Requirements

- Neovim >= 0.10
- [Microsoft AL Language Extension] for VS Code (provides the language server
  binary)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "abonckus/al.nvim",
    ft = "al",
    dependencies = {
        "MunifTanjim/nui.nvim",
        "nvim-neotest/nvim-nio",
    },
    opts = {},
}
```

### With debugging support

```lua
{
    "abonckus/al.nvim",
    ft = "al",
    dependencies = {
        "MunifTanjim/nui.nvim",
        "nvim-neotest/nvim-nio",
        "mfussenegger/nvim-dap",
        "rcarriga/nvim-dap-ui",
        "theHamsta/nvim-dap-virtual-text",
    },
    opts = {},
}
```

### With multi-project workspace support

```lua
{
    "abonckus/al.nvim",
    ft = "al",
    dependencies = {
        "MunifTanjim/nui.nvim",
        "nvim-neotest/nvim-nio",
        "abonckus/code-workspace.nvim",
    },
    opts = {},
}
```

## Configuration

All options with their defaults:

```lua
require("al").setup({
    -- Path to VS Code extensions directory.
    -- The plugin scans this for the AL Language extension.
    vscodeExtensionsPath = "~\\.vscode\\extensions\\",

    integrations = {
        luasnip = true,
    },

    lsp = {
        telemetryLevel = "all",       -- "none" | "crash" | "error" | "all"
        browser = "SystemDefault",    -- "SystemDefault" | "Chrome" | "Firefox"
                                      -- | "Edge" | "EdgeBeta"
        inlayHintsParameterNames = true,
        inlayHintsFunctionReturnTypes = true,
        semanticFolding = true,
        extendGoToSymbolInWorkspace = true,
        extendGoToSymbolInWorkspaceResultLimit = 100,
        extendGoToSymbolInWorkspaceIncludeSymbolFiles = true,
        log = {
            path = "",
            level = "Normal",         -- "Debug" | "Verbose" | "Normal"
                                      -- | "Warning" | "Error"
        },
    },

    workspace = {
        alResourceConfigurationSettings = {
            assemblyProbingPaths = { "./.netpackages" },
            codeAnalyzers = {
                "${CodeCop}",
                "${analyzerFolder}BusinessCentral.LinterCop.dll",
            },
            enableCodeAnalysis = true,
            backgroundCodeAnalysis = true,
            packageCachePaths = { "./.alpackages" },
            ruleSetPath = ".vscode/ruleset.json",
            enableCodeActions = true,
            incrementalBuild = false,
            outputAnalyzerStatistics = false,
            enableExternalRulesets = true,
        },
    },

    -- Multi-project workspace settings (used with code-workspace.nvim)
    multiproject = {
        -- Relative path to per-project settings file (read for
        -- alResourceConfigurationSettings overrides per folder)
        settings_path = ".vscode/settings.json",
        -- Maximum time (ms) to wait for a project closure to load
        closure_timeout_ms = 300000,
    },
})
```

## Commands

All commands use the `:AL` prefix.

| Command                    | Description                                    |
|----------------------------|------------------------------------------------|
| `:AL build`                | Build the current AL package                   |
| `:AL downloadSymbols`      | Download symbols (prompts for launch config)   |
| `:AL clearCredentialsCache`| Clear cached credentials in the language server|
| `:AL lsp`                  | Display LSP client info and settings           |
| `:AL definition`           | Go to definition of symbol under cursor        |

## Multi-project Workspaces

al.nvim supports multi-project workspaces through integration with
[code-workspace.nvim]. When you open a `.code-workspace` file, al.nvim:

1. Starts a single AL Language Server instance for all projects
2. Sends `al/loadManifest` for each project folder
3. Computes project-reference closures from `app.json` dependencies
4. Switches the active workspace on `BufEnter` (100ms debounce)
5. Sends `workspace/didChangeConfiguration` for dependency folders
6. Shows server progress notifications during closure loading

### How it works

Each workspace folder with an `app.json` is treated as an AL project. When you
open a file in a project, al.nvim computes which other workspace projects are
dependencies (by matching `app.json` dependency IDs) and sends the full closure
to the server via `al/setActiveWorkspace`.

The server's `rootPath` is set to the first AL project folder in the workspace
(alphabetically), matching VS Code's behavior.

### Per-project settings

Each project can override workspace-level `alResourceConfigurationSettings` by
placing them in a settings file (default `.vscode/settings.json`) under the key
`al.alResourceConfigurationSettings`. Global defaults are merged with
per-project settings, with per-project values taking precedence.

### Example workspace

```
my-workspace/
├── my-workspace.code-workspace
├── Cloud/
│   ├── app.json
│   ├── .vscode/settings.json
│   └── src/
├── Test/
│   ├── app.json          (depends on Cloud)
│   ├── .vscode/settings.json
│   └── src/
└── DemoApp/
    ├── app.json          (depends on Cloud)
    └── src/
```

Opening a file in `Test/` sends a closure of `[Test, Cloud]` to the server.
Opening a file in `Cloud/` sends a closure of `[Cloud]` only.

## Debugging

al.nvim routes DAP traffic through a Go proxy binary to solve stdio handle
crashes in AL EditorServices. The proxy is bundled in `bin/` for all platforms:

| Platform       | Binary                       |
|----------------|------------------------------|
| Windows        | `al-debug-proxy.exe`         |
| Linux          | `al-debug-proxy`             |
| macOS (Intel)  | `al-debug-proxy-darwin`      |
| macOS (ARM)    | `al-debug-proxy-darwin-arm64`|

Debug configurations are read from `.vscode/launch.json`. Set `"type": "al"` in
your launch configuration.

```vim
:DapToggleBreakpoint    " Set breakpoints
:DapContinue            " Start debugging
```

For technical details on the proxy, see [DEBUGGING.md](DEBUGGING.md).

### Building the proxy from source

Requires Go 1.21+:

```bash
cd proxy-src && ./build.sh     # Unix
cd proxy-src && build.bat      # Windows
```

## Project structure

```
your-al-project/
├── app.json              AL app manifest
├── .alpackages/          Symbol packages
├── .vscode/
│   ├── launch.json       Debug configurations
│   ├── settings.json     Per-project settings (multi-project)
│   └── ruleset.json      Code analysis rules
└── src/
    └── *.al
```

## Dependencies

| Plugin | Purpose | Required |
|--------|---------|----------|
| [nui.nvim] | UI for symbol download and auth menus | Yes |
| [nvim-nio] | Async I/O for multi-project and debugging | Yes |
| [code-workspace.nvim] | Multi-project workspace detection | For multi-project |
| [nvim-dap] | Debug Adapter Protocol | For debugging |
| [nvim-dap-ui] | Debug UI | For debugging |
| [nvim-dap-virtual-text] | Inline debug values | For debugging |
| [nvim-treesitter] + [tree-sitter-al] | Syntax highlighting | Optional |
| [LuaSnip] | AL snippets | Optional |
| [lsp-output.nvim] | LSP server log viewer | Optional |

## License

See [LICENSE](LICENSE).

<!-- link references -->
[Microsoft AL Language Extension]: https://marketplace.visualstudio.com/items?itemName=ms-dynamics-smb.al
[code-workspace.nvim]: https://github.com/abonckus/code-workspace.nvim
[nui.nvim]: https://github.com/MunifTanjim/nui.nvim
[nvim-nio]: https://github.com/nvim-neotest/nvim-nio
[nvim-dap]: https://github.com/mfussenegger/nvim-dap
[nvim-dap-ui]: https://github.com/rcarriga/nvim-dap-ui
[nvim-dap-virtual-text]: https://github.com/theHamsta/nvim-dap-virtual-text
[nvim-treesitter]: https://github.com/nvim-treesitter/nvim-treesitter
[tree-sitter-al]: https://github.com/SShadowS/tree-sitter-al
[LuaSnip]: https://github.com/L3MON4D3/LuaSnip
[lsp-output.nvim]: https://github.com/abonckus/lsp-output.nvim
