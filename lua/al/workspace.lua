local Utils = require("al.utils")

---@class al.Workspace
---@field root string
---@field client_id number
---@field settings table
local M = {}
M.__index = M

M.active = ""
M.workspaces = {}
M.hasProjectClosureLoaded = {} ---@type table<string, boolean>

---@param client_id number
---@param root string
M.new = function(client_id, root)
    local self = setmetatable({
        root = root,
        client_id = client_id,
        settings = {},
    }, M)
    return self
end

---@param client vim.lsp.Client
---@param buf integer
M.get_root = function(client, buf)
    local uri = vim.uri_from_bufnr(buf)
    for _, ws in ipairs(client.workspace_folders or {}) do
        if (uri .. "/"):sub(1, #ws.uri + 1) == ws.uri .. "/" then
            return ws.name
        end
    end
    return client.root_dir
end

M.get = function(client, buf)
    local root = vim.fs.normalize(M.get_root(client, buf))
    local client_id = type(client) == "number" and client or client.id
    local id = client_id .. root

    if not M.workspaces[id] then
        M.workspaces[id] = M.new(client_id, root)
    end

    return M.workspaces[id]
end

---@param opts {buf?:number, path?:string}
function M.find(opts)
    if opts.buf then
        local Lsp = require("al.lsp")
        local clients = Utils.get_clients({ bufnr = opts.buf })
        clients = vim.tbl_filter(function(client)
            return client and Lsp.supports(client)
        end, clients)
        local client = clients[1]
        return client and M.get(client.id, M.get_root(client, opts.buf))
    elseif opts.path then
        for _, ws in pairs(M.workspaces) do
            if ws:has(opts.path) then
                return ws
            end
        end
    end
end

---@param path string
function M:has(path)
    path = vim.fs.normalize(path)
    local dirs = { self.root } ---@type string[]
    for _, dir in ipairs(dirs) do
        if (path .. "/"):sub(1, #dir + 1) == dir .. "/" then
            return true
        end
    end
end

---@param client vim.lsp.Client
---@param buf integer
M.is_active = function(client, buf)
    local ws = M.get(client, buf)
    local id = ws.client_id .. ws.root
    return M.active == id
end

---@param client vim.lsp.Client
---@param buf integer
M.set_active = function(client, buf)
    local ws = M.get(client, buf)

    local additional_settings = {
        workspacePath = ws.root,
        setActiveWorkspace = true,
        expectedProjectReferenceDefinitions = {},
        activeWorkspaceClosure = {
            ws.root,
        },
    }
    local settings = vim.tbl_extend("force", {}, ws.settings or {}, client.settings or {}, additional_settings)
    local request = {
        currentWorkspaceFolderPath = {
            uri = {
                ["$mid"] = 1,
                fsPath = ws.root,
                _sep = 1,
                external = "file:///" .. ws.root,
                scheme = "file",
                path = ws.root,
            },
            name = ws.root,
            index = 0,
        },
        settings = settings,
    }

    client.request(client, "al/setActiveWorkspace", request, M.on_set_active_response)
end

---@param err? lsp.ResponseError
---@param ctx lsp.HandlerContext
---@param result any
---@param config? table
function M.on_set_active_response(err, result, ctx, config)
    if result and not result.success then
        local msg = err and err.message or "unknown error"
        Utils.error("al: Failed to set active workspace. " .. msg)
    end
    if not result then
        return
    end

    local client = vim.lsp.get_client_by_id(ctx.client_id)
    local ws = M.get(client, ctx.bufnr)
    local id = ws.client_id .. ws.root

    M.active = id

    if not client then
        Utils.error("al: No AL language server attached to the current buffer.")
        return
    end

    if not M.hasProjectClosureLoaded[ws.root] then
        client.request(
            client,
            "al/hasProjectClosureLoadedRequest",
            { workspacePath = ws.root },
            function(closure_err, closure_result)
                M.hasProjectClosureLoaded[ws.root] = closure_result and closure_result.loaded or false
            end
        )
    end
end

return M
