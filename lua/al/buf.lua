local Lsp = require("al.lsp")
local Workspace = require("al.workspace")

local M = {}

---@type table<number,number>
M.attached = {}
M.sequence = 0

M.setup = function()
    local group = vim.api.nvim_create_augroup("al", { clear = true })
    vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
        group = group,
        callback = function(ev)
            local client = vim.lsp.get_client_by_id(ev.data.client_id)
            if client and Lsp.supports(client) then
                if ev.event == "LspAttach" then
                    M.on_attach(client, ev.buf)
                else
                    M.attached[ev.buf] = nil
                end
            end
        end,
    })
end

---@param client vim.lsp.Client
---@param buf integer
M.on_attach = function(client, buf)
    if vim.bo[buf].filetype ~= "al" then
        return
    end
    M.set_active_file(client, buf)
    if M.attached[buf] then
        return
    end

    M.attached[buf] = buf

    vim.api.nvim_buf_attach(buf, false, {
        on_detach = function()
            M.attached[buf] = nil
        end,
    })

    Lsp.attach(client)

    if not require("al.multiproject").workspace_root() and not Workspace.is_active(client, buf) then
        Workspace.set_active(client, buf)
    end
end

M.set_active_file = function(client, buf)
    if vim.bo[buf].filetype ~= "al" then
        return
    end
    local params = {
        textDocument = {
            uri = "file:///" .. vim.api.nvim_buf_get_name(buf),
        },
        sequence = M.sequence,
    }
    client.request("al/didChangeActiveDocument", params, function() end)
    M.sequence = M.sequence + 1
end

return M
