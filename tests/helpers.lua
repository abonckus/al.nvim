local M = {}

--- Create a mock LSP client that records requests.
---@param opts? { id?: number, responses?: table<string, { err?: table, result?: table }> }
---@return table
function M.make_mock_client(opts)
    opts = opts or {}
    local client = {
        id = opts.id or 1,
        name = "al_ls",
        offset_encoding = "utf-16",
        requests = {},
        request = function(self, method, params, cb)
            table.insert(self.requests, { method = method, params = params })
            local response = opts.responses and opts.responses[method]
            if cb then
                vim.schedule(function()
                    if response then
                        cb(response.err, response.result, { client_id = self.id, params = params })
                    else
                        cb(nil, { success = true }, { client_id = self.id, params = params })
                    end
                end)
            end
            return true, #self.requests
        end,
        request_sync = function(self, method, params, timeout)
            table.insert(self.requests, { method = method, params = params })
            local response = opts.responses and opts.responses[method]
            if response then
                return { response.result }
            end
            return { { success = true } }
        end,
    }
    return client
end

--- Capture vim.notify messages during a test.
---@return { messages: { msg: string, level: number }[], restore: fun() }
function M.capture_notify()
    local captured = { messages = {} }
    local orig = vim.notify
    vim.notify = function(msg, level)
        table.insert(captured.messages, { msg = msg, level = level or vim.log.levels.INFO })
    end
    captured.restore = function()
        vim.notify = orig
    end
    return captured
end

--- Stub Lsp.get_client_for_buf to return a mock client.
---@param client table|nil
---@return fun() restore function
function M.stub_lsp_client(client)
    local Lsp = require("al.lsp")
    local orig = Lsp.get_client_for_buf
    Lsp.get_client_for_buf = function()
        return client
    end
    return function()
        Lsp.get_client_for_buf = orig
    end
end

--- Stub vim.lsp.get_clients to return mock clients.
---@param clients table[]
---@return fun() restore function
function M.stub_get_clients(clients)
    local orig = vim.lsp.get_clients
    vim.lsp.get_clients = function()
        return clients
    end
    return function()
        vim.lsp.get_clients = orig
    end
end

--- Stub vim.ui.select to auto-pick an item.
---@param index number|nil index to pick (nil = cancel)
---@return fun() restore function
function M.stub_ui_select(index)
    local orig = vim.ui.select
    vim.ui.select = function(items, opts, cb)
        if index then
            cb(items[index], index)
        else
            cb(nil, nil)
        end
    end
    return function()
        vim.ui.select = orig
    end
end

--- Stub vim.ui.input to return a value.
---@param value string|nil
---@return fun() restore function
function M.stub_ui_input(value)
    local orig = vim.ui.input
    vim.ui.input = function(opts, cb)
        cb(value)
    end
    return function()
        vim.ui.input = orig
    end
end

--- Stub vim.ui.open to record URL.
---@return { url: string|nil, restore: fun() }
function M.stub_ui_open()
    local captured = { url = nil }
    local orig = vim.ui.open
    vim.ui.open = function(url)
        captured.url = url
    end
    captured.restore = function()
        vim.ui.open = orig
    end
    return captured
end

--- Stub vim.fn.inputsecret to return a value.
---@param value string
---@return fun() restore function
function M.stub_inputsecret(value)
    local orig = vim.fn.inputsecret
    vim.fn.inputsecret = function()
        return value
    end
    return function()
        vim.fn.inputsecret = orig
    end
end

--- Wait for scheduled callbacks to run.
function M.flush()
    vim.wait(100, function()
        return false
    end, 10)
end

return M
