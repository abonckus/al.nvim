local M = {}

M.setup = function()
    local ok, _ = pcall(require, "luasnip")
    if not ok then
        return
    end

    local snippet_path = debug.getinfo(1).source:sub(2):gsub("integrations/luasnip.lua", "luasnippets")
    require("luasnip.loaders.from_lua").lazy_load({ paths = snippet_path })
end

return M
