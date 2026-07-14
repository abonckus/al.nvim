local M = {}

-- al/gotodefinition on a base-app / symbol object resolves to an `al-preview://`
-- URI instead of a real file on disk. VS Code serves those virtual documents with
-- a TextDocumentContentProvider that calls the `al/previewDocument` LSP request and
-- shows `result.content`. We mirror that on BufReadCmd so the jump lands on the
-- object's source instead of an empty buffer. nvim keeps the buffer name verbatim,
-- so `args.file` is the exact URI the server expects back.

---@param bufnr integer
---@param uri string
local function load(bufnr, uri)
    -- Marks the buffer so al.buf skips active-document bookkeeping for it, and
    -- doubles as guard against LSP attach side effects. Set before filetype below.
    vim.b[bufnr].al_preview = true
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].buftype = "nofile"

    -- ponytail: first al_ls client; per-project routing only if it ever matters.
    local client = vim.lsp.get_clients({ name = "al_ls" })[1]
    if not client then
        vim.notify("al: no al_ls client to load " .. uri, vim.log.levels.WARN)
        return
    end

    -- Synchronous: BufReadCmd must leave the buffer populated before it returns,
    -- otherwise the caller (al/gotodefinition) positions the cursor on a line that
    -- doesn't exist yet -> "Invalid cursor line: out of range".
    -- Note the capital `Uri` key and `content` field — matches the AL extension.
    local resp = client:request_sync("al/previewDocument", { Uri = uri }, 5000, bufnr)
    if not resp or resp.err or type(resp.result) ~= "table" or not resp.result.content then
        vim.notify("al: could not load preview for " .. uri, vim.log.levels.WARN)
        return
    end

    local lines = vim.split((resp.result.content:gsub("\r\n", "\n")), "\n", { plain = true })
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].modified = false
    vim.bo[bufnr].readonly = true
    vim.bo[bufnr].filetype = "al"

    -- Attach the running client so gotodefinition/hover work *inside* the preview,
    -- like VS Code. al.buf skips its active-doc bookkeeping via the al_preview marker.
    vim.lsp.buf_attach_client(bufnr, client.id)
end

local SCHEME = "al-preview://"

--- Identity key for an al-preview URI, ignoring the app-context segment. The
--- server returns e.g. `.../Cloud/Table/9650/...` or `.../<appId>/Table/9650/...`
--- for the *same* object depending on where the jump originates; keying on the
--- rest keeps both on one buffer instead of spawning a duplicate.
---@param uri string
---@return string
local function key(uri)
    local head, _ctx, rest = uri:match("^(al%-preview://[^/]+)/([^/]+)/(.+)$")
    return rest and (head .. "/*/" .. rest) or uri
end

--- Buffer to jump to for an LSP location filename. For al-preview URIs, reuse an
--- already-open buffer for the same object; otherwise fall back to bufadd.
---@param filename string
---@return integer
function M.bufnr_for(filename)
    if filename:sub(1, #SCHEME) == SCHEME then
        local want = key(filename)
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
            local name = vim.api.nvim_buf_get_name(b)
            if name:sub(1, #SCHEME) == SCHEME and key(name) == want then
                return b
            end
        end
    end
    return vim.fn.bufadd(filename)
end

function M.setup()
    vim.api.nvim_create_autocmd("BufReadCmd", {
        group = vim.api.nvim_create_augroup("al_preview", { clear = true }),
        pattern = "al-preview://*",
        callback = function(args)
            load(args.buf, args.file)
        end,
    })
end

M._load = load

return M
