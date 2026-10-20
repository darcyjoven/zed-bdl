; Genero Form Specification (.per) — syntax highlights for Zed
;
; 节点名与关键字全部取自 tree-sitter-per 的 src/node-types.json。
; 该 grammar 比真实 Genero 语法窄（例如 KEYS 小节是 `F1 = "Help"` 而非
; `KEY F1 ... ACTION ...`），query 必须严格贴合 grammar，否则整份 query
; 编译失败、高亮全无。改完请跑 tests/verify-queries.mjs。

; ---------------------------------------------------------------------------
; 基础
; ---------------------------------------------------------------------------
(comment) @comment

(string) @string
(number) @number
(number_with_unit) @number

; ---------------------------------------------------------------------------
; 标点与运算符
; ---------------------------------------------------------------------------
["(" ")" "[" "]" "{" "}"] @punctuation.bracket
["," ";" "."] @punctuation.delimiter

[
  "="
  "<"
  ">"
  "<="
  ">="
  "<>"
  "!="
  "*"
  "-"
  ":"
  "@"
] @operator

; ---------------------------------------------------------------------------
; 小节关键字
; ---------------------------------------------------------------------------
[
  "SCHEMA"
  "DATABASE"
  "LAYOUT"
  "SCREEN"
  "TABLES"
  "ATTRIBUTES"
  "INSTRUCTIONS"
  "KEYS"
  "ACTION"
  "DEFAULTS"
  "TOPMENU"
  "TOOLBAR"
] @keyword

; END 用 control 语义，让嵌套层次在一眼扫过时更清楚
"END" @keyword.control

; ---------------------------------------------------------------------------
; 布局容器
; ---------------------------------------------------------------------------
[
  "VBOX"
  "HBOX"
  "GROUP"
  "FOLDER"
  "PAGE"
  "GRID"
  "SCROLLGRID"
  "TABLE"
  "TREE"
] @keyword

; ---------------------------------------------------------------------------
; item 类型（EDIT / LABEL / CHECKBOX …）
; ---------------------------------------------------------------------------
(item_type) @type.builtin

[
  "AGGREGATE"
  "BUTTON"
  "BUTTONEDIT"
  "CANVAS"
  "CHECKBOX"
  "COMBOBOX"
  "DATEEDIT"
  "EDIT"
  "FIELD"
  "IMAGE"
  "LABEL"
  "PROGRESSBAR"
  "RADIOGROUP"
  "SLIDER"
  "SPINEDIT"
  "TEXTEDIT"
  "TIMEEDIT"
  "WEBCOMPONENT"
  "PHANTOM"
] @type.builtin

; ---------------------------------------------------------------------------
; 菜单元素
; ---------------------------------------------------------------------------
[
  "COMMAND"
  "SEPARATOR"
  "ITEM"
] @keyword

; ---------------------------------------------------------------------------
; 属性名与属性值
; ---------------------------------------------------------------------------

; TEXT="..." / FORMAT="..." / REQUIRED …
(attribute
  name: (name) @property)

; 布尔属性（REQUIRED / UPSHIFT …）单独成项
(attribute
  (boolexpr) @constant.builtin)

; 属性值
(attribute
  value: (value) @string.special)

(value) @string.special
(value_list) @string.special

; ---------------------------------------------------------------------------
; item tag（字段名）与绑定列
; ---------------------------------------------------------------------------

; EDIT f01 = customer.order_no —— 左边是 tag，右边是数据库列
(attribute_item
  tag: (name) @variable)

(untyped_attribute_item
  tag: (identifier) @variable)

(attribute_item
  field: (field_ref
    (name) @property))

(untyped_attribute_item
  field: (field_ref
    (name) @property))

(phantom_item
  (field_ref
    (name) @property))

; field_ref 里的 * （table.*）
(field_ref
  "*" @operator)

; ---------------------------------------------------------------------------
; SCREEN RECORD / TABLES / KEYS
; ---------------------------------------------------------------------------
(screen_record_entry
  name: (name) @function)

(screen_record_entry
  (field_ref
    (name) @variable))

(table_entry
  (identifier) @type)

(key_entry
  key: (key_name
    (identifier) @constant))

(key_entry
  label: (string) @string)

; ---------------------------------------------------------------------------
; 菜单名与动作名
; ---------------------------------------------------------------------------
(menu_group
  name: (identifier) @property)

(menu_item
  name: (identifier) @property)

(toolbar_item
  name: (identifier) @property)

(action_default_entry
  name: (name) @property)

; ---------------------------------------------------------------------------
; LAYOUT 内部
;
; 布局里的标签文本有屏幕坐标语义，Zed 的 highlights 只上色不改文本，
; 所以这里可以放心标记；但 indents.scm 与格式化绝不能动它。
; ---------------------------------------------------------------------------
(layout_tag) @tag
(area_text) @text.literal
(row_separator) @punctuation.special

; ---------------------------------------------------------------------------
; 类型子句
; ---------------------------------------------------------------------------
(type_clause
  "TYPE" @keyword)

(type_clause
  "LIKE" @keyword.operator)

(datatype) @type.builtin

(datetime_qualifier) @type.builtin

[
  "YEAR"
  "MONTH"
  "DAY"
  "HOUR"
  "MINUTE"
  "SECOND"
  "FRACTION"
] @keyword

[
  "CHARACTERS"
  "LINES"
  "COLUMNS"
  "PIXELS"
  "POINTS"
] @keyword

; ---------------------------------------------------------------------------
; 其它
; ---------------------------------------------------------------------------
"FORMONLY" @constant.builtin

[
  "TRUE"
  "FALSE"
  "NULL"
] @constant.builtin

[
  "NOT"
  "AND"
  "OR"
  "WHERE"
  "BY"
  "TO"
  "LIKE"
  "WITHOUT"
  "INPUT"
] @keyword.operator

[
  "SIZE"
  "TITLE"
  "RECORD"
  "SAMPLE"
  "DEFAULT"
  "DELIMITERS"
] @keyword
