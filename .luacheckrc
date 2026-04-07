-- luacheck configuration for al.nvim
-- https://luacheck.readthedocs.io/en/stable/config.html

std = "luajit"

-- Neovim injects `vim` as a global at runtime
globals = { "vim" }

-- Ignore unused arguments: LSP callbacks always have (err, result, ctx, config)
-- signatures even when only some arguments are used
ignore = { "212" }
