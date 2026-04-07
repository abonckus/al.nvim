local M = {}

M.setup = function()
    local ok = pcall(require, "noice")
    if not ok then
        return
    end

    local orig = vim.lsp.handlers["window/logMessage"]
    vim.lsp.handlers["window/logMessage"] = function(err, result, ctx, cfg)
        local client = vim.lsp.get_client_by_id(ctx.client_id)
        if client and client.name == "al_ls" then
            -- Route to noice log only (visible via :Noice log), no popup
            vim.notify(result.message, vim.log.levels.TRACE, { title = "AL" })
            return
        end
        if orig then
            return orig(err, result, ctx, cfg)
        end
    end
end

return M
