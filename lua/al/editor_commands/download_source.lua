local Util = require("al.utils")
local Lsp = require("al.lsp")

local download_source = function()
    local buf = vim.api.nvim_get_current_buf()
    local client = Lsp.get_client_for_buf(buf)
    if not client then
        Util.error("No AL language server attached to the current buffer.")
        return
    end

    local params = {
        configuration = nil,
    }

    Util.info("Downloading source...")
    client:request("al/downloadSource", params, function(err, result)
        if err then
            Util.error("Download source failed: " .. (err.message or vim.inspect(err)))
            return
        end

        if not result or not result.success then
            Util.error("Download source failed.")
            return
        end

        -- Apply workspace edits if present
        if result.changes then
            vim.lsp.util.apply_workspace_edit(result.changes, client.offset_encoding)
        end

        -- Create new files if present
        if result.newFiles then
            for _, file in ipairs(result.newFiles) do
                if file.fileName and file.content then
                    local dir = vim.fn.fnamemodify(file.fileName, ":h")
                    vim.fn.mkdir(dir, "p")
                    local f = io.open(file.fileName, "w")
                    if f then
                        f:write(file.content)
                        f:close()
                    end
                end
            end
        end

        Util.info("Source downloaded successfully.")
    end)
end

return download_source
