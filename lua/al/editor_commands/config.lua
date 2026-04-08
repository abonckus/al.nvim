local State = require("al.state")
local Util = require("al.utils")

---@param args string[]
---@param configs al.LaunchConfiguration[]
local set_config = function(args, configs)
    if #configs == 0 then
        Util.error("No launch configurations found in launch.json")
        return
    end

    -- :AL config MyServer — set by name
    if #args > 0 and args[1] ~= "" then
        local name = table.concat(args, " ")
        for _, cfg in ipairs(configs) do
            if cfg.name == name then
                State.set_config(cfg)
                Util.info("Active configuration: " .. cfg.name)
                return
            end
        end
        Util.error("Configuration not found: " .. name)
        return
    end

    -- :AL config — show picker
    vim.ui.select(configs, {
        prompt = "Select launch configuration:",
        format_item = function(item)
            return item.name
        end,
    }, function(choice)
        if choice then
            State.set_config(choice)
            Util.info("Active configuration: " .. choice.name)
        end
    end)
end

return set_config
