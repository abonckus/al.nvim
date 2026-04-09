local Util = require("al.utils")

local restart_lsp = function()
    local clients = vim.lsp.get_clients({ name = "al_ls" })
    if #clients == 0 then
        Util.warn("No AL language server running.")
        return
    end

    Util.info("Restarting AL language server...")

    for _, client in ipairs(clients) do
        vim.lsp.stop_client(client.id)
    end

    -- Defer to let clients detach, then re-trigger FileType on all AL buffers.
    -- This restarts the LSP via vim.lsp.enable. In multi-project mode,
    -- the LspAttach autocmd in multiproject.lua handles re-sending
    -- loadManifest and switching the active workspace.
    vim.defer_fn(function()
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "al" then
                vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
            end
        end
        Util.info("AL language server restarted.")
    end, 500)
end

return restart_lsp
