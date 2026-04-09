local Util = require("al.utils")
local Lsp = require("al.lsp")
local Picker = require("al.picker")

--- Insert an event subscriber signature at the cursor.
---@param item table
local function insert_subscriber(item)
    if not item.subscriber_signature and not item.signature then
        return
    end
    local text = item.subscriber_signature or item.signature
    local lines = vim.split(text, "\n")
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(0, row, row, false, lines)
end

--- Preview showing the subscriber signature in AL syntax.
local function preview_signature(ctx)
    if ctx.item.subscriber_signature then
        ctx.preview:set_lines(vim.split(ctx.item.subscriber_signature, "\n"))
        ctx.preview:highlight({ ft = "al" })
    elseif ctx.item.signature then
        ctx.preview:set_lines(vim.split(ctx.item.signature, "\n"))
        ctx.preview:highlight({ ft = "al" })
    else
        ctx.preview:set_lines({ "No preview available" })
    end
end

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
                text = (ep.name or "Unknown") .. " " .. (ep.signature or ""),
                name = ep.name,
                signature = ep.signature,
                subscriber_signature = ep.subscriberSignature,
                path = ep.path,
                location = ep.location,
            }
        end

        Picker.pick(items, {
            title = "AL Event Publishers",
            source = "al_event_publishers",
            preview = preview_signature,
            on_confirm = insert_subscriber,
        })
    end)
end

return event_publishers
