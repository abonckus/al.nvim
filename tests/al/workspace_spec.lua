describe("al.workspace nil root", function()
    local Workspace

    before_each(function()
        package.loaded["al.workspace"] = nil
        Workspace = require("al.workspace")
    end)

    -- Git diff buffers (fugitive://, gitsigns://, ...) have non-file URIs that
    -- match no workspace folder. A client started without a root_dir must not
    -- crash LspAttach handling.
    local diff_count = 0
    local function diff_buf()
        diff_count = diff_count + 1
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buf, ("fugitive:///tmp/repo/.git//src/Page%d.al"):format(diff_count))
        return buf
    end

    it("get_root returns nil when the client has no root", function()
        local client = { id = 1, name = "al_ls", root_dir = nil, workspace_folders = nil }
        assert.is_nil(Workspace.get_root(client, diff_buf()))
    end)

    it("get returns nil instead of erroring when the client has no root", function()
        local client = { id = 1, name = "al_ls", root_dir = nil, workspace_folders = nil }
        assert.has_no.errors(function()
            assert.is_nil(Workspace.get(client, diff_buf()))
        end)
    end)

    it("is_active returns false when the client has no root", function()
        local client = { id = 1, name = "al_ls", root_dir = nil, workspace_folders = nil }
        assert.has_no.errors(function()
            assert.is_false(Workspace.is_active(client, diff_buf()))
        end)
    end)

    it("still resolves a root for a client with root_dir", function()
        local client = { id = 2, name = "al_ls", root_dir = "/tmp/proj", workspace_folders = nil }
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buf, "/tmp/proj/src/Page.al")
        assert.are.equal("/tmp/proj", Workspace.get_root(client, buf))
    end)
end)
