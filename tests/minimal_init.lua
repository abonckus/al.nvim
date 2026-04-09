vim.opt.rtp:prepend(".")

local lazy = vim.fn.stdpath("data") .. "/lazy"
for _, dep in ipairs({ "plenary.nvim", "nvim-nio" }) do
    vim.opt.rtp:prepend(lazy .. "/" .. dep)
end

vim.filetype.add({ extension = { al = "al" } })

-- Prevent plugin auto-setup during tests (LSP, debugger, multiproject
-- all produce errors when VS Code extensions / DAP are unavailable)
vim.g._al_testing = true
