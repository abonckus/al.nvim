local Util = require("al.utils")
local Lsp = require("al.lsp")

--- Show results in a snacks picker, telescope, or quickfix fallback.
---@param items table[]
---@param opts { title: string }
local function show_in_picker(items, opts)
    -- Try snacks.picker first
    local snacks_ok, Snacks = pcall(require, "snacks")
    if snacks_ok and Snacks.picker then
        Snacks.picker.pick({
            source = "al_symbol_search",
            title = opts.title,
            items = items,
            format = function(item)
                return {
                    { item.name or "Unknown", "Function" },
                    " ",
                    { item.kind or "", "Type" },
                    " ",
                    { item.detail or "", "Comment" },
                }
            end,
            preview = "file",
            confirm = "jump",
        })
        return
    end

    -- Try telescope
    local telescope_ok, pickers = pcall(require, "telescope.pickers")
    if telescope_ok then
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values
        local previewers = require("telescope.previewers")

        pickers
            .new({}, {
                prompt_title = opts.title,
                finder = finders.new_table({
                    results = items,
                    entry_maker = function(item)
                        local display = (item.name or "Unknown")
                        if item.kind then
                            display = display .. " [" .. item.kind .. "]"
                        end
                        return {
                            value = item,
                            display = display,
                            ordinal = item.name or "",
                            filename = item.file,
                            lnum = item.pos and item.pos[1] or 1,
                            col = item.pos and item.pos[2] or 0,
                        }
                    end,
                }),
                previewer = conf.grep_previewer({}),
                sorter = conf.generic_sorter({}),
            })
            :find()
        return
    end

    -- Fallback: quickfix
    local qf_items = {}
    for _, item in ipairs(items) do
        qf_items[#qf_items + 1] = {
            text = (item.name or "Unknown") .. (item.kind and (" [" .. item.kind .. "]") or ""),
            filename = item.file or "",
            lnum = item.pos and item.pos[1] or 1,
            col = item.pos and item.pos[2] or 0,
        }
    end
    vim.fn.setqflist({}, " ", { title = opts.title, items = qf_items })
    vim.cmd("botright copen")
end

---@param args string[]
local symbol_search = function(args)
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

        -- Map LSP results to picker items
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

        show_in_picker(items, {
            title = "AL Symbol Search: " .. query,
        })
    end)
end

return symbol_search
