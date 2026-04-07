---@class al.Config.mod: al.Config
local M = {}

---@alias al.LSP.LogLevel "Debug" | "Verbose" | "Normal" | "Warning" | "Error"
---@alias al.LSP.TelemetryLevel "none" | "crash" | "error" | "all"
---@alias al.LSP.Browser "SystemDefault" | "Chrome" | "Firefox" | "Edge" | "EdgeBeta"

---@class al.Config.LSP
---@field telemetryLevel al.LSP.TelemetryLevel
---@field browser al.LSP.Browser
---@field inlayHintsParameterNames boolean
---@field inlayHintsFunctionReturnTypes boolean
---@field semanticFolding boolean
---@field extendGoToSymbolInWorkspace boolean
---@field extendGoToSymbolInWorkspaceResultLimit integer
---@field extendGoToSymbolInWorkspaceIncludeSymbolFiles boolean
---@field log {path: string, level: al.LSP.LogLevel }

---@class al.Config.Multiproject
---@field settings_path string

---@class al.Config
---@field lsp al.Config.LSP
---@field multiproject al.Config.Multiproject
local defaults = {
    vscodeExtensionsPath = "~\\.vscode\\extensions\\",
    integrations = {
        luasnip = true,
        noice = true,
    },
    workspace = {
        alResourceConfigurationSettings = {
            assemblyProbingPaths = {
                "./.netpackages",
            },
            codeAnalyzers = {
                "${CodeCop}",
                "${analyzerFolder}BusinessCentral.LinterCop.dll",
            },
            enableCodeAnalysis = true,
            backgroundCodeAnalysis = true,
            packageCachePaths = {
                "./.alpackages",
            },
            ruleSetPath = ".vscode/ruleset.json",
            enableCodeActions = true,
            incrementalBuild = false,
            outputAnalyzerStatistics = false,
            enableExternalRulesets = true,
        },
    },
    lsp = {
        telemetryLevel = "all",
        browser = "SystemDefault",
        inlayHintsParameterNames = true,
        inlayHintsFunctionReturnTypes = true,
        semanticFolding = true,
        extendGoToSymbolInWorkspace = true,
        extendGoToSymbolInWorkspaceResultLimit = 100,
        extendGoToSymbolInWorkspaceIncludeSymbolFiles = true,
        log = {
            path = "",
            level = "Normal",
        },
    },
    multiproject = {
        settings_path = ".vscode/settings.json",
    },
}

---@class al.LaunchConfiguration
M.default_launch_cfg = {
    name = "",
    type = "al",
    request = "launch",
    publishOnly = false,
    isRad = false,
    justDebug = false,
    -- Core server connection settings
    server = "http://bcserver",
    port = 7049,
    serverInstance = "",
    tenant = "default",
    primaryTenantDomain = "",
    applicationFamily = "",
    authentication = "MicrosoftEntraID",
    -- Startup object settings
    startupObjectId = 22,
    startupObjectType = "Page",
    startupCompany = "",
    -- Schema and publishing settings
    schemaUpdateMode = "Synchronize",
    dependencyPublishingOption = "Default",
    forceUpgrade = false,
    useSystemSessionForDeployment = false,
    -- Debugging settings
    breakOnError = "All",
    breakOnErrorBehaviour = false, -- Keep for backward compatibility
    breakOnRecordWrite = false,
    enableSqlInformationDebugger = true,
    enableLongRunningSqlStatements = true,
    longRunningSqlStatementsThreshold = 500,
    numberOfSqlStatements = 10,
    -- Browser and URL settings
    launchBrowser = true,
    usePublicURLFromServer = true,
    validateServerCertificate = true,
    -- Environment settings
    environmentName = "",
    environmentType = nil, -- Can be "OnPrem", "Sandbox", or "Production"
    sandboxName = "", -- Deprecated but kept for compatibility
    -- Network and timeout settings
    disableHttpRequestTimeout = false,
    -- Snapshot settings
    snapshotFileName = "",
    -- Legacy/compatibility settings
    projectReferenceDefinitions = {},
    useInteractiveLogin = true,
    isResolved = true,
}

M.language_extension_version = ""

---@type al.Config
local options

---@param opts? al.Config
function M.setup(opts)
    ---@type al.Config
    options = vim.tbl_deep_extend("force", {}, options or defaults, opts or {})

    vim.api.nvim_create_user_command("AL", function(...)
        require("al.cmd").execute(...)
    end, {
        nargs = "*",
        complete = function(...)
            return require("al.cmd").complete(...)
        end,
        desc = "al.nvim",
    })

    -- vim.keymap.set("n", "<leader>ab", "<cmd>AL build<cr>", {
    -- 	desc = "Build AL package",
    -- })

    vim.schedule(function()
        require("al.lsp").setup()
        require("al.debugger").setup()
        require("al.buf").setup()
        require("al.integrations").setup()
    end)
    return options
end

return setmetatable(M, {
    __index = function(_, key)
        options = options or M.setup()
        return options[key]
    end,
})
