local Config = require("al.config")
local Lsp = require("al.lsp")
local Workspace = require("al.workspace")
local Util = require("al.utils")

local dap = require("dap")
local dap_virtual_text = require("nvim-dap-virtual-text")
local dapui = require("dapui")

local build_package = require("al.editor_commands.build")
local auth = require("al.editor_commands.auth")

local M = {}

function M.setup()
    dap_virtual_text.setup()

    dapui.setup()

    dap.listeners.after.initialize.al = function()
        dapui.open()
    end

    dap.listeners.after.terminate.al = function()
        dapui.close()
    end

    dap.listeners.after.event_terminated.al = function()
        dapui.close()
    end

    dap.listeners.after.event_exited.al = function()
        dapui.close()
    end

    dap.adapters.al = function(callback, config)
        local auth_result = auth(config)
        if auth_result ~= "success" then
            Util.error("Authentication failed: " .. auth_result)
        end

        build_package()

        callback({
            type = "executable",
            command = M.cmd(),
            args = M.args(),
            options = {
                cwd = vim.fn.getcwd(),
            },
            enrich_config = function(config, on_config)
                local final_config = vim.deepcopy(config)
                final_config = vim.tbl_extend("force", Config.default_launch_cfg, final_config)
                if final_config.breakOnError == "None" then
                    final_config.breakOnError = false
                end
                if final_config.breakOnRecordWrite == "None" then
                    final_config.breakOnRecordWrite = false
                end
                on_config(final_config)
            end,
        })
    end

    -- Set up basic DAP configurations for AL
    dap.configurations.al = {
        {
            type = "al",
            request = "launch",
            name = "Launch AL Debugger",
            server = "http://bcserver",
            port = 7049,
            serverInstance = "",
            tenant = "default",
            authentication = "MicrosoftEntraID",
            startupObjectId = 22,
            startupObjectType = "Page",
            breakOnError = true,
            breakOnRecordWrite = false,
            enableSqlInformationDebugger = true,
            enableLongRunningSqlStatements = true,
            longRunningSqlStatementsThreshold = 500,
            numberOfSqlStatements = 10,
            launchBrowser = true,
            usePublicURLFromServer = true,
            validateServerCertificate = true,
        },
    }
end

function M.cmd()
    return M.get_proxy_path()
end

function M.args()
    local fname = vim.api.nvim_buf_get_name(0)
    local ws = Workspace.find({ path = fname })

    return {
        Lsp.find_lsp_path(Config.vscodeExtensionsPath, true),
        "/telemetryLevel:" .. Config.lsp.telemetryLevel,
        "/browser:" .. Config.lsp.browser,
        "/inlayHintsParameterNames:" .. tostring(Config.lsp.inlayHintsParameterNames),
        "/inlayHintsFunctionReturnTypes:" .. tostring(Config.lsp.inlayHintsFunctionReturnTypes),
        "/semanticFolding:" .. tostring(Config.lsp.semanticFolding),
        "/extendGoToSymbolInWorkspace:" .. tostring(Config.lsp.extendGoToSymbolInWorkspace),
        "/extendGoToSymbolInWorkspaceResultLimit:" .. tostring(Config.lsp.extendGoToSymbolInWorkspaceResultLimit),
        "/extendGoToSymbolInWorkspaceIncludeSymbolFiles:"
        .. tostring(Config.lsp.extendGoToSymbolInWorkspaceIncludeSymbolFiles),
        "/startDebugging",
        "/projectRoot:" .. ws.root,
    }
end

-- Get the path to the appropriate proxy binary for the current platform
function M.get_proxy_path()
    local plugin_path = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") .. "../.."
    local os_name = vim.loop.os_uname().sysname:lower()

    if os_name:match("windows") then
        -- Check if .exe exists, otherwise use .bat (temporary fallback)
        local exe_path = plugin_path .. "/bin/al-debug-proxy.exe"
        local bat_path = plugin_path .. "/bin/al-debug-proxy.bat"
        if vim.fn.filereadable(exe_path) == 1 then
            return exe_path
        else
            return bat_path
        end
    elseif os_name:match("darwin") then
        -- Check if we're on Apple Silicon
        local arch = vim.loop.os_uname().machine:lower()
        if arch:match("arm64") then
            return plugin_path .. "/bin/al-debug-proxy-darwin-arm64"
        else
            return plugin_path .. "/bin/al-debug-proxy-darwin"
        end
    else
        return plugin_path .. "/bin/al-debug-proxy"
    end
end

-- Helper function to create a DAP configuration with custom settings
function M.create_config(opts)
    opts = opts or {}
    return vim.tbl_extend("force", Config.default_launch_cfg, {
        name = opts.name or "AL Debugger",
    }, opts)
end

return M
