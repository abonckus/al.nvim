local M = {}

M.setup = function()
    local ok, _ = pcall(require, "nvim-treesitter")
    if not ok then
        return
    end

    vim.api.nvim_create_autocmd("User", {
        pattern = "TSUpdate",
        callback = function()
            require("nvim-treesitter.parsers").al = {
                install_info = {
                    url = "https://github.com/SShadowS/tree-sitter-al",
                    queries = "queries",
                },
            }
        end,
    })
end

return M
