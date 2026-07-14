describe("al.lsp.find_lsp_path", function()
    local lsp
    local orig_uname, orig_scandir, orig_scandir_next, orig_expand

    before_each(function()
        package.loaded["al.lsp"] = nil
        lsp = require("al.lsp")
        orig_uname = vim.uv.os_uname
        orig_scandir = vim.uv.fs_scandir
        orig_scandir_next = vim.uv.fs_scandir_next
        orig_expand = vim.fn.expand

        -- Fake an extensions dir containing one AL extension folder.
        vim.fn.expand = function(p) return p end
        vim.uv.fs_scandir = function() return true end
        local yielded = false
        vim.uv.fs_scandir_next = function()
            if yielded then return nil end
            yielded = true
            return "ms-dynamics-smb.al-15.0.0", "directory"
        end
    end)

    after_each(function()
        vim.uv.os_uname = orig_uname
        vim.uv.fs_scandir = orig_scandir
        vim.uv.fs_scandir_next = orig_scandir_next
        vim.fn.expand = orig_expand
    end)

    local function stub_os(sysname)
        vim.uv.os_uname = function() return { sysname = sysname, machine = "x86_64" } end
    end

    it("uses bin/darwin on macOS", function()
        stub_os("Darwin")
        local path = lsp.find_lsp_path("~/.vscode/extensions/", false)
        assert.is_truthy(path:match("/bin/darwin/Microsoft%.Dynamics%.Nav%.EditorServices%.Host$"))
    end)

    it("uses bin/win32 with backslashes on Windows", function()
        stub_os("Windows_NT")
        local path = lsp.find_lsp_path("~\\.vscode\\extensions\\", false)
        assert.is_truthy(path:match("\\bin\\win32\\Microsoft%.Dynamics%.Nav%.EditorServices%.Host$"))
    end)

    it("uses bin/linux on Linux", function()
        stub_os("Linux")
        local path = lsp.find_lsp_path("~/.vscode/extensions/", true)
        assert.is_truthy(path:match("/bin/linux/Microsoft%.Dynamics%.Nav%.EditorServices%.Host%.dll$"))
    end)
end)
