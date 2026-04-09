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

        if not result or (type(result) == "table" and vim.tbl_isempty(result)) then
            Util.info("No symbols found for: " .. query)
            return
        end

        local items = {}
        if vim.islist(result) then
            for _, item in ipairs(result) do
                local file = item.location and item.location.uri and vim.uri_to_fname(item.location.uri) or ""
                local lnum = item.location and item.location.range and (item.location.range.start.line + 1) or 1
                local col = item.location and item.location.range and (item.location.range.start.character + 1) or 1
                items[#items + 1] = {
                    text = (item.name or item.label or "") .. " " .. (item.kind or ""),
                    name = item.name or item.label,
                    kind = item.kind,
                    detail = item.detail,
                    file = file,
                    pos = { lnum, col },
                }
            end
        end

        if #items == 0 then
            Util.info("Symbol search results:\n" .. vim.inspect(result))
            return
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
