local random = math.random

---@class al.Utils.mod
local M = {}

function M.create_uuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and random(0, 0xf) or random(8, 0xb)
        return string.format("%x", v)
    end)
end

---@param msg string|string[]
---@param opts? NotifyOpts
function M.notify(msg, opts)
    opts = opts or {}
    msg = type(msg) == "table" and table.concat(msg, "\n") or msg
    ---@cast msg string
    msg = vim.trim(msg)
    return vim[opts.once and "notify_once" or "notify"](msg, opts.level, {
        title = opts.title or "al.nvim",
        on_open = function(win)
            vim.wo[win].conceallevel = 3
            vim.wo[win].concealcursor = "n"
            vim.wo[win].spell = false
            vim.treesitter.start(vim.api.nvim_win_get_buf(win), "markdown")
        end,
    })
end

---@param msg string|string[]
---@param opts? NotifyOpts
function M.warn(msg, opts)
    M.notify(msg, vim.tbl_extend("keep", { level = vim.log.levels.WARN }, opts or {}))
end

---@param msg string|string[]
---@param opts? NotifyOpts
function M.error(msg, opts)
    M.notify(msg, vim.tbl_extend("keep", { level = vim.log.levels.ERROR }, opts or {}))
end

---@param msg string|string[]
---@param opts? NotifyOpts
function M.info(msg, opts)
    M.notify(msg, vim.tbl_extend("keep", { level = vim.log.levels.INFO }, opts or {}))
end

M.get_clients = vim.lsp.get_clients

function M.read_json_file(path)
    local f = assert(io.open(path))
    local content = f:read("*a")
    f:close()
    local table_content = vim.json.decode(content)
    return table_content
end

return M
