local Util = require("al.utils")
local Lsp = require("al.lsp")
local Picker = require("al.picker")

local symbol_search
---@param args string[]
symbol_search = function(args)
    local buf = vim.api.nvim_get_current_buf()
    local client = Lsp.get_client_for_buf(buf)
    if not client then
        Util.error("No AL language server attached to the current buffer.")
        return
    end

    local query = table.concat(args or {}, " ")
    if query == "" then
        vim.ui.input({ prompt = "Symbol search: " }, function(input)
            if input and input ~= "" then
                symbol_search({ input })
            end
        end)
        return
    end

    local params = {
        query = query,
    }

    client:request("al/symbolSearch", params, function(err, result)
        if err then
            Util.error("Symbol search failed: " .. (err.message or vim.inspect(err)))
            return
        end

        -- Result is { message, succeeded, symbols } — symbols is the list
        local symbols = result.symbols or (vim.islist(result) and result) or nil
        if not symbols or #symbols == 0 then
            Util.info("No symbols found for: " .. query)
            return
        end

        local items = {}
        for _, item in ipairs(symbols) do
            items[#items + 1] = {
                text = (item.name or "") .. " " .. (item.kind or ""),
                name = item.name,
                kind = item.kind,
                signature = item.signature,
                detail = item.containerName and item.containerName ~= "" and item.containerName or item.docSummary,
                file = item.path or "",
                pos = { 1, 0 },
            }
        end

        Picker.pick(items, {
            title = "AL Symbol Search: " .. query,
            source = "al_symbol_search",
            format = function(item)
                return {
                    { item.name or "Unknown", "Function" },
                    { " ", "Normal" },
                    { item.kind or "", "Type" },
                    { " ", "Normal" },
                    { item.detail or "", "Comment" },
                }
            end,
        })
    end)
end

return symbol_search
