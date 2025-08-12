; Identifiers
(identifier) @variable
(quoted_identifier) @variable

; Object declarations
(table_declaration) @keyword
(table_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type)

(tableextension_declaration) @keyword
(tableextension_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type
  base_object: [(identifier) (quoted_identifier)] @type)

(codeunit_declaration) @keyword
(codeunit_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type)

(page_declaration) @keyword
(page_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type)

(pageextension_declaration) @keyword
(pageextension_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type
  base_object: [(identifier) (quoted_identifier)] @type)

(pagecustomization_declaration) @keyword
(pagecustomization_declaration
  object_name: [(identifier) (quoted_identifier)] @type
  target_page: [(identifier) (quoted_identifier)] @type)

(query_declaration) @keyword
(query_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type)

(report_declaration) @keyword
(report_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type)

(reportextension_declaration) @keyword
(reportextension_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type
  base_object: [(identifier) (quoted_identifier)] @type)

(enum_declaration) @keyword
(enum_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type)

(enumextension_declaration) @keyword
(enumextension_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type
  base_object: [(identifier) (quoted_identifier)] @type)

(xmlport_declaration) @keyword
(xmlport_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type)

(interface_declaration) @keyword
(interface_declaration
  object_name: [(identifier) (quoted_identifier)] @type)

(controladdin_declaration) @keyword
(controladdin_declaration
  object_name: [(identifier) (quoted_identifier)] @type)

(permissionset_declaration) @keyword
(permissionset_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type)

(permissionsetextension_declaration) @keyword
(permissionsetextension_declaration
  object_id: (integer) @number
  object_name: [(identifier) (quoted_identifier)] @type)

(entitlement_declaration) @keyword
(entitlement_declaration
  object_name: [(identifier) (quoted_identifier)] @type)

(profile_declaration) @keyword
(profile_declaration
  object_name: [(identifier) (quoted_identifier)] @type)

(profileextension_declaration) @keyword
(profileextension_declaration
  object_name: [(identifier) (quoted_identifier)] @type)

(dotnet_declaration) @keyword

(assembly_declaration) @keyword
(assembly_declaration
  name: (_) @type)

; Namespace and using statements
(namespace_declaration) @keyword
(namespace_declaration
  name: (namespace_name) @namespace)

(using_statement) @keyword.import

; Sections
(var_section) @keyword
(field_section) @keyword
(keys) @keyword
(fieldgroups_section) @keyword
(actions_section) @keyword
(layout_section) @keyword
(dataset_section) @keyword
(rendering_section) @keyword
(labels_section) @keyword
(elements_section) @keyword
(dataitem_section) @keyword
(column_section) @keyword
(requestpage_section) @keyword
(fixed_section) @keyword
(area_section) @keyword
(group_section) @keyword
(part_section) @keyword
(systempart_section) @keyword
(usercontrol_section) @keyword
(repeater_section) @keyword
(cuegroup_section) @keyword
(grid_section) @keyword
(filter_section) @keyword

; Field and other declarations
(field_declaration) @keyword
(field_declaration
  id: (integer) @number
  name: [(identifier) (quoted_identifier)] @variable.member
  type: (_) @type)

(key_declaration) @keyword
(fieldgroup_declaration) @keyword
(variable_declaration) @keyword
(const) @keyword
(type_declaration) @keyword
(enum_value_declaration) @keyword

; Enum values
(enum_value_declaration
  value_id: (integer) @number
  value_name: [(identifier) (quoted_identifier) (string_literal)] @constant)

; Procedures and triggers
(procedure) @keyword
(procedure
  name: (name (_) @function))

(procedure_header) @keyword
(attributed_procedure) @keyword
(interface_procedure) @keyword
(controladdin_procedure) @keyword

(trigger_declaration) @keyword
(trigger_declaration
  name: (_) @function)

(field_trigger_declaration) @keyword
(onrun_trigger) @keyword
(attributed_trigger) @keyword
(named_trigger) @keyword
(attributed_onrun_trigger) @keyword

; Action declarations
(action_declaration) @keyword
(action_declaration
  name: [(identifier) (quoted_identifier)] @function)

(actionref_declaration) @keyword
(systemaction_declaration) @keyword
(fileuploadaction_declaration) @keyword
(customaction_declaration) @keyword
(separator_action) @keyword

; Control flow statements
(assignment_statement) @keyword
(assignment_statement
  operator: (_) @operator)

(if_statement) @conditional
(case_statement) @conditional
(for_statement) @repeat
(foreach_statement) @repeat
(while_statement) @repeat
(repeat_statement) @repeat
(with_statement) @keyword
(exit_statement) @keyword.return
(empty_statement) @keyword
(asserterror_statement) @keyword

; Expressions
(assignment_expression) @operator
(conditional_expression) @conditional
(logical_expression) @operator
(comparison_expression) @operator
(additive_expression) @operator
(multiplicative_expression) @operator
(unary_expression) @operator
(parenthesized_expression) @punctuation.bracket
(call_expression) @function.call
(member_expression) @property
(subscript_expression) @punctuation.bracket
(range_expression) @operator
(enum_value_expression) @constant
(field_reference_expression) @variable.member
(const_expression) @constant

; Filter expressions
(filter_or_expression) @operator
(filter_and_expression) @operator
(filter_equal_expression) @operator
(filter_not_equal_expression) @operator
(filter_less_than_expression) @operator
(filter_greater_than_expression) @operator
(filter_less_than_or_equal_expression) @operator
(filter_greater_than_or_equal_expression) @operator
(filter_range_expression) @operator
(simple_filter_expression) @operator
(filter_expression_function) @function.call

; Function calls and member access
(call_expression
  function: [(identifier) (member_expression)] @function.call)

(member_expression
  object: (_) @variable
  property: [(identifier) (quoted_identifier)] @property)

; Enum references
(enum_value_expression) @constant

; Data types
(basic_type) @keyword
(array_type) @keyword
(list_type) @keyword
(dictionary_type) @keyword
(record_type) @keyword
(recordref_type) @keyword
(fieldref_type) @keyword
(option_type) @keyword
(text_type) @keyword
(code_type) @keyword
(enum_type) @keyword
(interface_type) @keyword
(controladdin_type) @keyword
(dotnet_type) @keyword
(codeunit_type) @keyword
(page_type) @keyword
(report_type) @keyword
(xmlport_type) @keyword
(query_type) @keyword
(testpage_type) @keyword
(testrequestpage_type) @keyword

; Type specifications
(type_specification) @keyword
(type_specification (_ reference: (_) @type)) @keyword

; Parameters
(parameter
  parameter_name: (_) @parameter
  parameter_type: (type_specification (_ reference: (_) @type)) @keyword)

(parameter 
  parameter_type: (type_specification) @keyword)

(parameter
  parameter_type: (type_specification
    (_ reference: (_) @type)))

(parameter_list) @punctuation.bracket
(argument_list) @punctuation.bracket

; Modifiers
(modifier) @keyword

; Properties
(property) @property
(caption_property) @property
(description_property) @property
(enabled_property) @property
(visible_property) @property
(editable_property) @property
(source_table_property) @property
(page_type_property) @property
(usage_category_property) @property
(application_area_property) @property
(data_caption_expression_property) @property
(insert_allowed_property) @property
(modify_allowed_property) @property
(delete_allowed_property) @property
(tool_tip_property) @property
(image_property) @property
(promoted_property) @property
(promoted_category_property) @property
(promoted_is_big_property) @property
(show_caption_property) @property
(table_type_property) @property
(query_type_property) @property
(direction_property) @property
(format_property) @property
(access_property) @property

; Implements clause
(implements_clause) @keyword
(implements_clause
  interface: (_) @type)

; Labels
(label_declaration
  name: (identifier) @label
  value: (string_literal) @string)

; Attributes
(attribute
  "[" @punctuation.bracket
  attribute_name: (identifier) @attribute
  "]" @punctuation.bracket)

(attribute_list) @attribute

; Operators
(comparison_operator) @operator
(filter_operator) @operator
(in_operator) @operator
["+"] @operator
["-"] @operator
["*"] @operator
["/"] @operator
["and"] @operator.word
["or"] @operator.word
["not"] @operator.word
["="] @operator
["<>"] @operator
["<"] @operator
[">"] @operator
["<="] @operator
[">="] @operator
[":="] @operator
["::"] @operator
["."] @operator
[","] @operator

; Literals
(string_literal) @string
(integer) @number
(decimal) @number
(biginteger) @number
(boolean) @boolean
(date_literal) @string.special
(datetime_literal) @string.special
(time_literal) @string.special
(duration_string) @string.special
(list_literal) @punctuation.bracket

; Comments
(comment) @comment
(multiline_comment) @comment

; Preprocessor directives
(pragma) @preproc
(preprocessor_file_conditional) @preproc
(preproc_if) @preproc
(preproc_elif) @preproc
(preproc_else) @preproc
(preproc_endif) @preproc
(preproc_region) @preproc
(preproc_endregion) @preproc
(preproc_not_expression) @preproc
(malformed_directive) @preproc

; Punctuation
["("] @punctuation.bracket
[")"] @punctuation.bracket
["["] @punctuation.bracket
["]"] @punctuation.bracket
["{"] @punctuation.bracket
["}"] @punctuation.bracket
[";"] @punctuation.delimiter
[","] @punctuation.delimiter
["."] @punctuation.delimiter
[":"] @punctuation.delimiter

; Error highlighting
(ERROR) @error
