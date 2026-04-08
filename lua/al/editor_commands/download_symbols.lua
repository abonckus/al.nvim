local Config = require("al.config")
local Util = require("al.utils")
local Lsp = require("al.lsp")

local auth = require("al.editor_commands.auth")

---@param cb fun(err: lsp.ResponseError, result: any, ctx: lsp.HandlerContext, config?: table)
local download_symbols_lsp_request = function(params, cb)
    local bufnr = vim.api.nvim_get_current_buf()
    local client = Lsp.get_client_for_buf(bufnr)
    if not client then
        Util.error("No AL language server attached to the current buffer.")
        return
    end
    client:request("al/downloadSymbols", params, cb)
end

local download_symbols_handler
download_symbols_handler = function(err, result, ctx, config)
    if err and err.data == 401 then
        Util.info("Needs authentication")
        coroutine.resume(coroutine.create(function()
            local auth_result = auth(ctx.params.configuration)
            if auth_result == "success" then
                download_symbols_lsp_request(ctx.params, download_symbols_handler)
            end
        end))
        return
    end

    if not err then
        if result.success then
            Util.info("Symbols have been downloaded")
        else
            Util.error("Could not download reference symbols.")
        end
    end
end

---@param config al.LaunchConfiguration
local download_symbols = function(config)
    local params = {
        configuration = config,
        browserInfo = {
            browser = Config.lsp.browser,
            incognito = false,
        },
        environmentInfo = {},
        force = true,
    }

    download_symbols_lsp_request(params, download_symbols_handler)
end

return download_symbols
