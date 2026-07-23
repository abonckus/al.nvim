local M = {}

local Config = require("al.config")
local Lsp = require("al.lsp")
local Dap = require("al.integrations.dap")

local h = vim.health

--- Report the Neovim version. 0.11 is the effective floor because
--- vim.lsp.config / vim.lsp.enable (lsp.lua) have no pre-0.11 fallback.
local function check_nvim()
    h.start("Neovim")
    if vim.fn.has("nvim-0.11") == 1 then
        h.ok("Neovim " .. tostring(vim.version()))
    else
        h.error(
            "Neovim 0.11+ required (LSP setup uses vim.lsp.config/enable with no fallback); found "
                .. tostring(vim.version())
        )
    end
end

--- Resolve the AL Language Server binary via the VS Code AL extension.
--- find_lsp_path does NOT stat the file, so stat it here to catch a matched
--- extension folder with a missing/renamed binary (a silent failure today).
local function check_lsp_server()
    h.start("AL language server (VS Code AL extension)")
    local base = Config.vscodeExtensionsPath
    local bin = Lsp.find_lsp_path(base, false)
    if not bin then
        h.error("AL extension not found under " .. vim.fn.expand(base), {
            "Install the 'AL Language' (ms-dynamics-smb.al) VS Code extension",
            "Or set vscodeExtensionsPath in setup()",
        })
        return
    end
    if vim.uv.fs_stat(bin) then
        h.ok(("AL extension v%s\n  server: %s"):format(tostring(Config.language_extension_version), bin))
    else
        h.error("AL extension folder found but server binary missing: " .. bin, {
            "Reinstall the 'AL Language' (ms-dynamics-smb.al) VS Code extension",
        })
    end
end

--- The Go debug proxy is optional (only debugging needs it).
local function check_debug_proxy()
    h.start("Debug proxy")
    local proxy = Dap.get_proxy_path()
    if vim.fn.filereadable(proxy) == 1 then
        h.ok("proxy binary: " .. proxy)
    else
        h.warn("Debug proxy binary not found: " .. proxy, {
            "Build it: cd al.nvim/proxy-src && build.bat (Windows) or ./build.sh (Unix)",
            "Only affects debugging; LSP and build work without it",
        })
    end
end

--- dotnet: needed by the debug proxy (execs `dotnet <EditorServices>.dll`)
--- and by the AL compiler tool. LSP host is a native exe and does not need it.
--- `al`: the AL compiler shipped as a dotnet global tool.
local function check_external_tools()
    h.start("External tools")

    if vim.fn.executable("dotnet") == 1 then
        h.ok("dotnet on PATH")
    else
        h.warn("dotnet not on PATH", { "Needed for debugging and the AL compiler tool; not needed for LSP" })
    end

    -- `al` collides with the .NET Framework Assembly Linker (al.exe), common on
    -- Windows dev boxes. Disambiguate via `al --version`: the BC AL CLI prints a
    -- bare semver as its first line; the Assembly Linker prints a "Microsoft (R)
    -- ... Assembly Linker" banner that does not start with a digit.
    if vim.fn.executable("al") == 1 then
        local first = vim.trim((vim.fn.system({ "al", "--version" }) or ""):match("^[^\r\n]*") or "")
        if first:match("^%d+%.%d+%.%d+") then
            h.ok("AL compiler tool (`al`) v" .. first)
        else
            h.warn("`al` on PATH is not the BC AL compiler (Assembly Linker?): " .. first, {
                "Expected Microsoft.Dynamics.BusinessCentral.Development.Tools",
                "Install: dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools",
            })
        end
    else
        h.warn("AL compiler tool (`al`) not on PATH", {
            "Install: dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools",
        })
    end
end

--- Verify each enabled integration's backing plugin is loadable.
--- treesitter additionally needs the `al` parser installed.
local function check_integrations()
    h.start("Optional integrations")
    local integ = Config.integrations or {}

    local function report(enabled, name, mod, hint)
        if not enabled then
            h.info(name .. ": disabled")
        elseif pcall(require, mod) then
            h.ok(name .. ": " .. mod .. " loaded")
        else
            h.warn(name .. ": '" .. mod .. "' not installed", hint and { hint } or nil)
        end
    end

    report(integ.dap, "dap", "dap", "Install nvim-dap for debugging")
    report(integ.luasnip, "luasnip", "luasnip", "Install L3MON4D3/LuaSnip for snippets")

    -- treesitter: plugin present AND the `al` parser installed.
    -- NOTE: vim.treesitter.language.add returns `true` when the parser loads and
    -- `nil` (no error thrown) when it is missing — so a bare `pcall(...)` truthiness
    -- test would false-OK. Check the RETURN value, not just that pcall didn't error.
    if not integ.treesitter then
        h.info("treesitter: disabled")
    elseif not pcall(require, "nvim-treesitter") then
        h.warn("treesitter: 'nvim-treesitter' not installed", { "Install nvim-treesitter/nvim-treesitter" })
    else
        local ok, added = pcall(vim.treesitter.language.add, "al")
        if ok and added then
            h.ok("treesitter: nvim-treesitter loaded, `al` parser installed")
        else
            h.warn("treesitter: `al` parser not installed", { "Run :TSUpdate al (parser: SShadowS/tree-sitter-al)" })
        end
    end
end

--- Report whether the current directory / buffer sits inside an AL project.
--- Informational only -- :checkhealth can be run from anywhere.
local function check_workspace()
    h.start("Workspace")
    local root = vim.fs.root(0, { "app.json", ".alpackages" })
    if root then
        h.ok("AL project root: " .. root)
    else
        h.info("No AL project (app.json / .alpackages) found from the current directory")
    end
end

function M.check()
    check_nvim()
    check_lsp_server()
    check_debug_proxy()
    check_external_tools()
    check_integrations()
    check_workspace()
end

return M
