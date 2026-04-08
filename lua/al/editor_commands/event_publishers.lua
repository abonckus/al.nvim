local Util = require("al.utils")
local Lsp = require("al.lsp")

local event_publishers = function()
    local buf = vim.api.nvim_get_current_buf()
    local client = Lsp.get_client_for_buf(buf)
    if not client then
        Util.error("No AL language server attached to the current buffer.")
        return
    end

    local params = {
        format = "Detailed",
    }

    Util.info("Fetching event publishers...")
    client:request("al/getEventPublishersRequest", params, function(err, result)
        if err then
            Util.error("Failed to get event publishers: " .. (err.message or vim.inspect(err)))
            return
        end

        if not result or #result == 0 then
            Util.info("No event publishers found.")
            return
        end

        local items = {}
        for _, ep in ipairs(result) do
            items[#items + 1] = {
                text = (ep.name or "Unknown") .. " — " .. (ep.signature or ""),
                filename = ep.path or "",
                lnum = ep.location
                        and ep.location.range
                        and ep.location.range.start
                        and (ep.location.range.start.line + 1)
                    or 1,
                col = ep.location
                        and ep.location.range
                        and ep.location.range.start
                        and (ep.location.range.start.character + 1)
                    or 1,
            }
        end

        vim.fn.setqflist({}, " ", {
            title = "AL Event Publishers",
            items = items,
        })
        vim.cmd("botright copen")
    end)
end

return event_publishers
