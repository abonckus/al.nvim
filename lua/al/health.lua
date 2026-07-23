-- lua/al/health.lua
local M = {}

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
    check_workspace()
end

return M
