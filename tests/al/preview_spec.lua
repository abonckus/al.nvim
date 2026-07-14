local helpers = require("tests.helpers")

describe("al.preview", function()
    local preview = require("al.preview")
    local uri = "al-preview://allang/Cloud/Table/9650/Custom Report Layout.dal"

    local function scratch()
        return vim.api.nvim_create_buf(false, true)
    end

    before_each(function()
        -- Names are reused across tests; wipe stale preview buffers to avoid
        -- "buffer name already in use" on nvim_buf_set_name.
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_get_name(b):match("^al%-preview://") then
                vim.api.nvim_buf_delete(b, { force = true })
            end
        end
    end)

    --- Mock al_ls client whose request_sync mirrors the real `{ err, result }` shape.
    ---@param response { err?: table, result?: table }
    local function mock_client(response)
        return {
            id = 1,
            name = "al_ls",
            requests = {},
            request_sync = function(self, method, params)
                table.insert(self.requests, { method = method, params = params })
                return response
            end,
        }
    end

    --- Stub vim.lsp.buf_attach_client so tests don't need a real client registry.
    local function stub_attach()
        local calls = {}
        local orig = vim.lsp.buf_attach_client
        vim.lsp.buf_attach_client = function(bufnr, id)
            table.insert(calls, { bufnr = bufnr, id = id })
            return true
        end
        return calls, function()
            vim.lsp.buf_attach_client = orig
        end
    end

    it("fills the buffer and attaches the client on success", function()
        local client = mock_client({ result = { content = "table 9650 X\r\n{\r\n}" } })
        local restore = helpers.stub_get_clients({ client })
        local attach_calls, restore_attach = stub_attach()
        local buf = scratch()

        preview._load(buf, uri)

        restore_attach()
        restore()
        assert.equals("al/previewDocument", client.requests[1].method)
        assert.equals(uri, client.requests[1].params.Uri)
        assert.same({ "table 9650 X", "{", "}" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        assert.equals("al", vim.bo[buf].filetype)
        assert.equals("nofile", vim.bo[buf].buftype)
        assert.is_false(vim.bo[buf].modifiable)
        assert.is_true(vim.b[buf].al_preview)
        assert.equals(1, #attach_calls)
        assert.equals(buf, attach_calls[1].bufnr)
        assert.equals(client.id, attach_calls[1].id)
    end)

    it("warns when no al_ls client is available", function()
        local restore = helpers.stub_get_clients({})
        local notify = helpers.capture_notify()
        local buf = scratch()

        preview._load(buf, uri)

        notify.restore()
        restore()
        assert.equals(1, #notify.messages)
        assert.equals(vim.log.levels.WARN, notify.messages[1].level)
    end)

    it("bufnr_for reuses one buffer for the same object across app contexts", function()
        local from = "al-preview://allang/Cloud/Table/9650/Custom Report Layout.dal"
        local to = "al-preview://allang/00000000000000000000000000000000/Table/9650/Custom Report Layout.dal"
        local buf = scratch()
        vim.api.nvim_buf_set_name(buf, from)

        assert.equals(buf, preview.bufnr_for(to))
        assert.equals(buf, preview.bufnr_for(from))
    end)

    it("bufnr_for keeps distinct objects on distinct buffers", function()
        local a = "al-preview://allang/Cloud/Table/9650/Custom Report Layout.dal"
        local b = "al-preview://allang/Cloud/Codeunit/50/Other.dal"
        local buf = scratch()
        vim.api.nvim_buf_set_name(buf, a)

        assert.is_true(buf ~= preview.bufnr_for(b))
    end)

    it("warns and does not attach when the response has an error", function()
        local client = mock_client({ err = { code = -32601, message = "boom" } })
        local restore = helpers.stub_get_clients({ client })
        local attach_calls, restore_attach = stub_attach()
        local notify = helpers.capture_notify()
        local buf = scratch()

        preview._load(buf, uri)

        notify.restore()
        restore_attach()
        restore()
        assert.equals(1, #notify.messages)
        assert.equals(vim.log.levels.WARN, notify.messages[1].level)
        assert.equals(0, #attach_calls)
    end)
end)
