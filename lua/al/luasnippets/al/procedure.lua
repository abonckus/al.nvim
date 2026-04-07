-- Snippet for creating AL procedure
-- "Snippet: Procedure": {
--     "prefix": "tprocedure",
--     "body": [
--         "${1:local} procedure ${2:MyProcedure}(${3})",
--         "var",
--         "\t${4:myInt}: ${5:Integer};",
--         "begin",
--         "\t$0",
--         "end;"
--     ],
--     "description": "Snippet: Procedure"
-- },

local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local fmt = require("luasnip.extras.fmt").fmt

return {
    s(
        {
            trig = "tprocedure",
            desc = "Snippet: Procedure",
        },
        fmt(
            [[
            {} procedure {}({})
            var
                {}: {};
            begin
                {}
            end;
        ]],
            {
                i(1, "local"),
                i(2, "MyProcedure"),
                i(3),
                i(4, "myInt"),
                i(5, "Integer"),
                i(0),
            }
        )
    ),
}
