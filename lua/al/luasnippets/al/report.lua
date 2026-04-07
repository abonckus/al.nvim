local ls = require("luasnip")

local s = ls.snippet
local i = ls.insert_node
local fmt = require("luasnip.extras.fmt").fmt

return {
    s(
        {
            trig = "treport",
            desc = "Snippet: Report",
        },
        fmt(
            [[
            report {id} {name}
            {{
                UsageCategory = {usage_category};
                ApplicationArea = {application_area};
                DefaultRenderingLayout = {layout_name};

                dataset
                {{
                    dataitem({data_item_name}, {source_table_name})
                    {{
                        column({column_name}, {source_field_name})
                        {{
                            {}
                        }}
                    }}
                }}

                requestpage
                {{
                    AboutTitle = '{}';
                    AboutText = '{}';
                    layout
                    {{
                        area(Content)
                        {{
                            group({})
                            {{
                                field({}, {})
                                {{
                                    {}
                                }}
                            }}
                        }}
                    }}

                    actions
                    {{
                        area({})
                        {{
                            action({})
                            {{
                                {}
                            }}
                        }}
                    }}
                }}

                rendering
                {{
                    layout({})
                    {{
                        Type = {};
                        LayoutFile = '{}';
                    }}
                }}

                var
                    {}: {};
            }}
        ]],
            {
                id = i(1, "Id"),
                name = i(2, "MyReport"),
                usage_category = i(3, "ReportsAndAnalysis,Administration,Documents,History,Lists,None,Tasks"),
                application_area = i(4, "All,Basic,Suite,Advanced"),
                layout_name = i(5, "LayoutName"),
                data_item_name = i(6, "DataItemName"),
                source_table_name = i(7, "SourceTableName"),
                column_name = i(8, "ColumnName"),
                source_field_name = i(9, "SourceFieldName"),
                i(10),
                i(11, "Teaching tip title"),
                i(12, "Teaching tip content"),
                i(13, "GroupName"),
                i(14, "SourceExpression"),
                i(15, "Name"),
                i(16),
                i(17, "processing"),
                i(18, "ActionName"),
                i(19),
                i(20, "LayoutName"),
                i(21, "Excel"),
                i(22, "mySpreadsheet.xlsx"),
                i(23, "myInt"),
                i(0, "Integer"),
            }
        )
    ),
}
