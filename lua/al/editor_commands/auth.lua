local Ui = require("al.ui")
local Lsp = require("al.lsp")

---@type "none" | "success" | "fail" | "cancelled"
local auth_result = "none"

local function username_co()
	local co = coroutine.running()

	Ui.show_input_username(function(value)
		coroutine.resume(co, value)
	end, function()
		coroutine.resume(co, nil)
	end)

	return coroutine.yield()
end

local function password_co()
	local co = coroutine.running()
	Ui.show_input_password(function(value)
		coroutine.resume(co, value)
	end, function()
		coroutine.resume(co, nil)
	end)

	return coroutine.yield()
end

---@param client? vim.lsp.Client
local check_authenticated = function(client, config)
	local co = coroutine.running()

	if not client then
		coroutine.resume(co, false)
		return
	end

	client:request("al/checkAuthenticated", config, function(err, result)
		coroutine.resume(co, result and result.authenticated)
	end)

	return coroutine.yield()
end

---@return "none" | "success" | "fail" | "cancelled"
local authenticate_co = function(config)
	auth_result = "none"

	local buf = vim.api.nvim_get_current_buf()
	---@type vim.lsp.Client?
	local client = Lsp.get_client_for_buf(buf)
	if not client then
		Ui.error("No AL language server attached to the current buffer.")
		auth_result = "fail"
		return auth_result
	end

	local check_result = check_authenticated(client, { configuration = config })
	if check_result then
		auth_result = "success"
		return auth_result
	end

	local username = username_co()
	if not username then
		auth_result = "cancelled"
		return auth_result
	end

	local password = password_co()

	if not password then
		auth_result = "cancelled"
		return auth_result
	end

	local params = {
		configuration = config,
		credentials = {
			username = username,
			password = password,
		},
	}

	local result = client:request_sync("al/saveUsernamePassword", params, 5000)
	if result and result[1] and result[1].error then
		auth_result = "fail"
	else
		auth_result = "success"
	end

	return auth_result
end

return authenticate_co
