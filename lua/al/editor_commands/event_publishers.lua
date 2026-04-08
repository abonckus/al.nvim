local Util = require("al.utils")
local Lsp = require("al.lsp")

--- Show results in a snacks picker, telescope, or quickfix fallback.
---@param items table[]
---@param opts { title: string, on_confirm?: fun(item: table) }
local function show_in_picker(items, opts)
    -- Try snacks.picker first
    local snacks_ok, Snacks = pcall(require, "snacks")
    if snacks_ok and Snacks.picker then
        Snacks.picker.pick({
            source = "al_event_publishers",
            title = opts.title,
            items = items,
            format = function(item)
                return {
                    { item.name or "Unknown", "Function" },
                    " ",
                    { item.signature or "", "Comment" },
                }
            end,
            preview = function(ctx)
                if ctx.item.subscriber_signature then
                    ctx.preview:set_lines(vim.split(ctx.item.subscriber_signature, "\n"))
                    ctx.preview:highlight({ ft = "al" })
                elseif ctx.item.signature then
                    ctx.preview:set_lines(vim.split(ctx.item.signature, "\n"))
                    ctx.preview:highlight({ ft = "al" })
                else
                    ctx.preview:set_lines({ "No preview available" })
                end
            end,
            confirm = function(picker, item)
                picker:close()
                if item and opts.on_confirm then
                    opts.on_confirm(item)
                end
            end,
        })
        return
    end

    -- Try telescope
    local telescope_ok, pickers = pcall(require, "telescope.pickers")
    if telescope_ok then
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")
        local previewers = require("telescope.previewers")

        pickers
            .new({}, {
                prompt_title = opts.title,
                finder = finders.new_table({
                    results = items,
                    entry_maker = function(item)
                        return {
                            value = item,
                            display = (item.name or "Unknown") .. " — " .. (item.signature or ""),
                            ordinal = (item.name or "") .. " " .. (item.signature or ""),
                        }
                    end,
                }),
                previewer = previewers.new_buffer_previewer({
                    define_preview = function(self, entry)
                        local text = entry.value.subscriber_signature or entry.value.signature or "No preview"
                        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(text, "\n"))
                        vim.bo[self.state.bufnr].filetype = "al"
                    end,
                }),
                sorter = conf.generic_sorter({}),
                attach_mappings = function(prompt_bufnr)
                    actions.select_default:replace(function()
                        local selection = action_state.get_selected_entry()
                        actions.close(prompt_bufnr)
                        if selection and opts.on_confirm then
                            opts.on_confirm(selection.value)
                        end
                    end)
                    return true
                end,
            })
            :find()
        return
    end

    -- Fallback: quickfix
    local qf_items = {}
    for _, item in ipairs(items) do
        qf_items[#qf_items + 1] = {
            text = (item.name or "Unknown") .. " — " .. (item.signature or ""),
            filename = item.path or "",
            lnum = item.location and item.location.range and item.location.range.start
                    and (item.location.range.start.line + 1)
                or 1,
        }
    end
    vim.fn.setqflist({}, " ", { title = opts.title, items = qf_items })
    vim.cmd("botright copen")
end

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

        -- Map LSP results to picker items
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

        show_in_picker(items, {
            title = "AL Event Publishers",
            on_confirm = insert_subscriber,
        })
    end)
end

return event_publishers
