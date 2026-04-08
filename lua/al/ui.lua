local M = {}

--- Show a selection menu for launch configurations.
---@param configs al.LaunchConfiguration[]
---@param on_submit fun(config: al.LaunchConfiguration)
---@param on_close? fun()
M.show_config_selection_menu = function(configs, on_submit, on_close)
    vim.ui.select(configs, {
        prompt = "Select launch configuration:",
        format_item = function(item)
            return item.name
        end,
    }, function(choice)
        if choice then
            on_submit(choice)
        elseif on_close then
            on_close()
        end
    end)
end

--- Prompt for username input.
---@param on_submit fun(value: string)
---@param on_cancel fun()
M.show_input_username = function(on_submit, on_cancel)
    vim.ui.input({ prompt = "Username: " }, function(input)
        if input and input ~= "" then
            on_submit(input)
        else
            on_cancel()
        end
    end)
end

--- Prompt for password input (masked).
---@param on_submit fun(value: string)
---@param on_cancel fun()
M.show_input_password = function(on_submit, on_cancel)
    vim.schedule(function()
        local input = vim.fn.inputsecret("Password: ")
        if input and input ~= "" then
            on_submit(input)
        else
            on_cancel()
        end
    end)
end

return M
