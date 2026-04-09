local Util = require("al.utils")

---@param config al.LaunchConfiguration
local open_in_browser = function(config)
    local server = config.server or ""
    local port = config.port or ""
    local instance = config.serverInstance or ""
    local tenant = config.tenant or "default"
    local company = config.startupCompany or ""

    -- Build URL based on whether it's SaaS (environmentName set) or on-prem
    local url
    if config.environmentName and config.environmentName ~= "" then
        -- SaaS: https://businesscentral.dynamics.com/{environmentName}
        url = string.format("https://businesscentral.dynamics.com/%s", config.environmentName)
    else
        -- On-prem: server:port/instance/?tenant=X&company=Y
        local base = server
        if port and port ~= "" and port ~= 0 then
            base = base .. ":" .. tostring(port)
        end
        if instance and instance ~= "" then
            base = base .. "/" .. instance
        end
        url = base .. "/?tenant=" .. tenant
        if company ~= "" then
            url = url .. "&company=" .. vim.uri_encode(company)
        end
    end

    Util.info("Opening: " .. url)
    if vim.fn.has("win32") == 1 then
        vim.fn.jobstart({ "rundll32", "url.dll,FileProtocolHandler", url }, { detach = true })
    else
        local _, err = vim.ui.open(url)
        if err then
            Util.error("Failed to open browser: " .. err)
        end
    end
end

return open_in_browser
