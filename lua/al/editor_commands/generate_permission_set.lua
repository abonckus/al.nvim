local Util = require("al.utils")
local Lsp = require("al.lsp")
local Workspace = require("al.workspace")

local generate_permission_set = function()
    local buf = vim.api.nvim_get_current_buf()
    local client = Lsp.get_client_for_buf(buf)
    if not client then
        Util.error("No AL language server attached to the current buffer.")
        return
    end

    local fname = vim.api.nvim_buf_get_name(0)
    local ws = Workspace.find({ path = fname })
    local project_dir = require("al.multiproject").project_for_buf(buf) or (ws and ws.root)
    if not project_dir then
        Util.error("Could not determine AL project directory.")
        return
    end

    local params = {
        currentWorkspacePath = project_dir,
    }

    Util.info("Generating permission set...")
    client:request("al/generatePermissionSetInALObject", params, function(err, result)
        if err then
            Util.error("Generate permission set failed: " .. (err.message or vim.inspect(err)))
            return
        end

        if not result or not result.success then
            Util.error("Generate permission set failed.")
            return
        end

        -- Apply workspace edits
        if result.changes then
            vim.lsp.util.apply_workspace_edit(result.changes, client.offset_encoding)
        end

        -- Create new files
        if result.newFiles then
            for _, file in ipairs(result.newFiles) do
                if file.fileName and file.content then
                    local dir = vim.fn.fnamemodify(file.fileName, ":h")
                    vim.fn.mkdir(dir, "p")
                    local f = io.open(file.fileName, "w")
                    if f then
                        f:write(file.content)
                        f:close()
                        -- Open the newly created file
                        vim.cmd("edit " .. vim.fn.fnameescape(file.fileName))
                    end
                end
            end
        end

        Util.info("Permission set generated.")
    end)
end

return generate_permission_set
