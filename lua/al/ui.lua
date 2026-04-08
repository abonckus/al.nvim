local M = {}

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
