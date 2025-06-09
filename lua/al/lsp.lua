---@type al.Config.mod
local Config = require("al.config")
---@type al.Utils.mod
local Utils = require("al.utils")
local Workspace = require("al.workspace")

local M = {}
M.attached = {} ---@type table<number, number>

---@param client? vim.lsp.Client
function M.assert(client)
    assert(M.supports(client), "al: Not a al_ls client??")
end

---@param client? vim.lsp.Client
function M.supports(client)
    return client and vim.tbl_contains({ "al_ls" }, client.name)
end

---@param client? vim.lsp.Client
function M.attach(client)
    if M.attached[client.id] then
        return
    end

    M.assert(client)

    M.attached[client.id] = client.id

    -- client.handlers = vim.tbl_extend("force", {}, client.handlers or {})

    -- M.set_handler(client, "workspace/configuration", M.on_workspace_configuration)
    -- M.set_handler(client, "al/setActiveWorkspace", M.on_set_active_workspace)
    M.set_handler(client, "al/progressNotification", M.on_progress_notification)
end

---@param err lsp.ResponseError
---@param result any
---@param ctx lsp.HandlerContext
function M.on_progress_notification(err, result, ctx)
    local kind = "report"
    if result.percent == 0 then
        kind = "begin"
    end
    if result.percent == 100 then
        kind = "end"
    end

    vim.api.nvim_exec_autocmds("LspProgress", {
        pattern = result.percent == 0 and "begin" or "end",
        modeline = false,
        data = {
            client_id = ctx.client_id,
            params = {
                token = "al_progress_" .. result.owner,
                value = {
                    kind = kind,
                    title = "AL loading",
                    cancellable = result.cancel,
                    message = result.message,
                    percentage = result.percent,
                },
            },
        },
    })
end

---@param client vim.lsp.Client
---@param type string
---@param handler fun(err?: lsp.ResponseError, result: any, ctx: lsp.HandlerContext, cfg?: table)
function M.set_handler(client, type, handler)
    if vim.fn.has("nvim-0.10") == 0 then
        if M.did_global_handler then
            return
        end
        M.did_global_handler = true
        local orig = vim.lsp.handlers[type]
        vim.lsp.handlers[type] = function(err, params, ctx, cfg)
            if M.attached[ctx.client_id] then
                return handler(err, params, ctx, cfg)
            end
            return orig(err, params, ctx, cfg)
        end
    else
        client.handlers[type] = handler
    end
end

function M.setup()
    vim.lsp.config.al_ls = {
        cmd = M.cmd(),
        filetypes = { "al" },
        root_markers = { "app.json", ".alpackages" },
        root_dir = function(bufnr, on_dir)
            local fname = vim.api.nvim_buf_get_name(bufnr)
            local has_al_project_cfg = function(path)
                local alpath = vim.fs.joinpath(path, "app.json")
                return (vim.uv.fs_stat(alpath) or {}).type == "file"
            end
            on_dir(vim.iter(vim.fs.parents(fname)):find(has_al_project_cfg) or vim.fs.root(0, ".alpackages"))
        end,
        single_file_support = true,
        settings = Config.workspace,
        -- init_options = {
        --     logging = { level = "trace" },
        --     trace = { server = "verbose" },
        -- },
    }

    vim.lsp.enable("al_ls")
end

function M.cmd()
    return {
        "dotnet",
        M.find_lsp_path(Config.vscodeExtensionsPath),
        "/telemetryLevel:" .. Config.lsp.telemetryLevel,
        "/browser:" .. Config.lsp.browser,
        "/inlayHintsParameterNames:" .. tostring(Config.lsp.inlayHintsParameterNames),
        "/inlayHintsFunctionReturnTypes:" .. tostring(Config.lsp.inlayHintsFunctionReturnTypes),
        "/semanticFolding:" .. tostring(Config.lsp.semanticFolding),
        "/extendGoToSymbolInWorkspace:" .. tostring(Config.lsp.extendGoToSymbolInWorkspace),
        "/extendGoToSymbolInWorkspaceResultLimit:" .. tostring(Config.lsp.extendGoToSymbolInWorkspaceResultLimit),
        "/extendGoToSymbolInWorkspaceIncludeSymbolFiles:"
        .. tostring(Config.lsp.extendGoToSymbolInWorkspaceIncludeSymbolFiles),
        "/sessionId:" .. (Utils.create_uuid()),
    }
end

function M.find_lsp_path(basePath)
    local path = ""
    for filename in io.popen('dir "' .. vim.fn.expand(basePath) .. '" /b /ad'):lines() do
        local match = filename:match("ms%-dynamics%-smb.al%-(.+)")
        if match then
            Config.language_extension_version = match
            path = vim.fn.expand(basePath)
                .. (basePath:sub(- #basePath) == "\\" and "\\" or "")
                .. filename
                .. "\\bin\\win32\\Microsoft.Dynamics.Nav.EditorServices.Host.dll"
        end
    end
    return path
end

function M.go_to_definition()
    local method = "al/gotodefinition"
    local util = require('vim.lsp.util')
    local lsp = vim.lsp
    local api = vim.api

    opts = opts or {}
    local bufnr = api.nvim_get_current_buf()
    local clients = lsp.get_clients({ method = method, bufnr = bufnr })
    if not next(clients) then
        vim.notify(lsp._unsupported_method(method), vim.log.levels.WARN)
        return
    end
    local win = api.nvim_get_current_win()
    local from = vim.fn.getpos('.')
    from[1] = bufnr
    local tagname = vim.fn.expand('<cword>')
    local remaining = #clients

    ---@type vim.quickfix.entry[]
    local all_items = {}

    ---@param result nil|lsp.Location|lsp.Location[]
    ---@param client vim.lsp.Client
    local function on_response(_, result, client)
        local locations = {}
        if result then
            locations = vim.islist(result) and result or { result }
        end
        local items = util.locations_to_items(locations, client.offset_encoding)
        vim.list_extend(all_items, items)
        remaining = remaining - 1
        if remaining == 0 then
            if vim.tbl_isempty(all_items) then
                vim.notify('No locations found', vim.log.levels.INFO)
                return
            end

            local title = 'LSP locations'
            if opts.on_list then
                assert(vim.is_callable(opts.on_list), 'on_list is not a function')
                opts.on_list({
                    title = title,
                    items = all_items,
                    context = { bufnr = bufnr, method = method },
                })
                return
            end

            if #all_items == 1 then
                local item = all_items[1]
                local b = item.bufnr or vim.fn.bufadd(item.filename)

                -- Save position in jumplist
                vim.cmd("normal! m'")
                -- Push a new item into tagstack
                local tagstack = { { tagname = tagname, from = from } }
                vim.fn.settagstack(vim.fn.win_getid(win), { items = tagstack }, 't')

                vim.bo[b].buflisted = true
                local w = win
                if opts.reuse_win then
                    w = vim.fn.win_findbuf(b)[1] or w
                    if w ~= win then
                        api.nvim_set_current_win(w)
                    end
                end
                api.nvim_win_set_buf(w, b)
                api.nvim_win_set_cursor(w, { item.lnum, item.col - 1 })
                vim._with({ win = w }, function()
                    -- Open folds under the cursor
                    vim.cmd('normal! zv')
                end)
                return
            end
            if opts.loclist then
                vim.fn.setloclist(0, {}, ' ', { title = title, items = all_items })
                vim.cmd.lopen()
            else
                vim.fn.setqflist({}, ' ', { title = title, items = all_items })
                vim.cmd('botright copen')
            end
        end
    end
    for _, client in ipairs(clients) do
        local params = util.make_position_params(win, client.offset_encoding)
        local body = {
            configuration = nil,
            browserInfo = {
                browser = Config.lsp.browser,
                incognito = Config.lsp.incognito,
            },
            environmentInfo = {},
            textDocumentPositionParams = params,
        }
        client:request(method, body, function(_, result)
            on_response(_, result, client)
        end)
    end
end

return M
