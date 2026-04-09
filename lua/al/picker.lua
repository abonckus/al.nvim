local M = {}

---@class al.PickerOpts
---@field title string
---@field source? string
---@field format? fun(item: table): table[]
---@field preview? string|fun(ctx: table)
---@field confirm? string|fun(picker: table, item: table)
---@field on_confirm? fun(item: table)
---@field entry_display? fun(item: table): string
---@field entry_ordinal? fun(item: table): string

--- Default format: name + signature
---@param item table
---@return table[]
local function default_format(item)
    return {
        { item.name or "Unknown", "Function" },
        { " ", "Normal" },
        { item.signature or item.kind or "", "Comment" },
    }
end

--- Default display for telescope entry
---@param item table
---@return string
local function default_display(item)
    local parts = { item.name or "Unknown" }
    if item.signature then
        parts[#parts + 1] = " — " .. item.signature
    elseif item.kind then
        parts[#parts + 1] = " [" .. item.kind .. "]"
    end
    return table.concat(parts)
end

--- Default ordinal for telescope filtering
---@param item table
---@return string
local function default_ordinal(item)
    return (item.name or "") .. " " .. (item.signature or item.kind or "")
end

--- Show items in snacks.picker, telescope, or quickfix fallback.
---@param items table[]
---@param opts al.PickerOpts
function M.pick(items, opts)
    local format_fn = opts.format or default_format
    local display_fn = opts.entry_display or default_display
    local ordinal_fn = opts.entry_ordinal or default_ordinal

    -- Try snacks.picker
    local snacks_ok, Snacks = pcall(require, "snacks")
    if snacks_ok and Snacks.picker then
        local pick_opts = {
            source = opts.source or "al_picker",
            title = opts.title,
            items = items,
            format = format_fn,
            preview = opts.preview or "file",
            confirm = opts.confirm or "jump",
        }

        -- Custom confirm with on_confirm callback
        if opts.on_confirm then
            pick_opts.confirm = function(picker, item)
                picker:close()
                if item then
                    opts.on_confirm(item)
                end
            end
        end

        Snacks.picker.pick(pick_opts)
        return
    end

    -- Try telescope
    local telescope_ok, pickers = pcall(require, "telescope.pickers")
    if telescope_ok then
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        local picker_opts = {
            prompt_title = opts.title,
            finder = finders.new_table({
                results = items,
                entry_maker = function(item)
                    return {
                        value = item,
                        display = display_fn(item),
                        ordinal = ordinal_fn(item),
                        filename = item.file or item.path or nil,
                        lnum = item.pos and item.pos[1] or nil,
                        col = item.pos and item.pos[2] or nil,
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
        }

        -- Add previewer if available
        if type(opts.preview) == "function" then
            local previewers = require("telescope.previewers")
            picker_opts.previewer = previewers.new_buffer_previewer({
                define_preview = function(self, entry)
                    opts.preview({
                        item = entry.value,
                        preview = {
                            set_lines = function(_, lines)
                                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
                            end,
                            highlight = function(_, o)
                                if o.ft then
                                    vim.bo[self.state.bufnr].filetype = o.ft
                                end
                            end,
                        },
                    })
                end,
            })
        elseif opts.preview == "file" then
            picker_opts.previewer = conf.grep_previewer({})
        end

        -- Custom confirm
        if opts.on_confirm then
            picker_opts.attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    if selection then
                        opts.on_confirm(selection.value)
                    end
                end)
                return true
            end
        end

        pickers.new({}, picker_opts):find()
        return
    end

    -- Fallback: quickfix
    local qf_items = {}
    for _, item in ipairs(items) do
        qf_items[#qf_items + 1] = {
            text = display_fn(item),
            filename = item.file or item.path or "",
            lnum = item.pos and item.pos[1] or 1,
            col = item.pos and item.pos[2] or 0,
        }
    end
    vim.fn.setqflist({}, " ", { title = opts.title, items = qf_items })
    vim.cmd("botright copen")
end

return M
