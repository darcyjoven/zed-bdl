; Genero Form — outline
;
; .per 的大纲按小节组织：LAYOUT / TABLES / ATTRIBUTES / INSTRUCTIONS …
; 每个 item 定义都进大纲，方便在表单里快速跳到某个字段。
;
; ── 关于 @item 的一个必须遵守的约束（P7-A-1）────────────────────────────
;
; Zed 用 @item 的**区间**构建大纲的父子关系。若同一份 query 产出两个区间
; 完全相同的 @item，Zed 会把后一个当成前一个的子节点，大纲出现假层级。
;
; 这个坑在 `PHANTOM table.column;` 上会触发：field_ref 有两个 name 子节点
;
;   (field_ref
;     (name ...)              ← 表名 formonly
;     column: (name ...))     ← 列名 p_flag
;
; 若规则只写 `(field_ref (name) @name)`，表名和列名都命中，
; 两个 match 的 @item 区间完全相同 → 假层级。
; 正确写法是**只绑 column 字段**，并把 @item 绑到列名节点：
;
;   ✗ (phantom_item (field_ref (name) @name)) @item
;   ✓ (phantom_item (field_ref column: (name) @name @item))
;
; tests/verify-queries.mjs 有断言守着这条规则（"@item 区间两两不同"）。

; item 定义：EDIT f01 = ...
;
; 这些是单个 item 的独立节点，不存在"一条语句多个名字"，
; 但为保持一致也把 @item 绑到名字节点，避免将来 grammar 变化时回归。
(attribute_item
  tag: (name) @name @item)

(untyped_attribute_item
  tag: (identifier) @name @item)

; PHANTOM：只取 column 字段（列名），表名不进大纲。
(phantom_item
  (field_ref
    column: (name) @name @item))

; SCREEN RECORD
(screen_record_entry
  name: (name) @name @item)

; 表
(table_entry
  (identifier) @name @item)

; 菜单：name 字段在 grammar 里是 `identifier | 关键字` 的联合，
; 直接绑 identifier 才合法（绑 (name) 会报 Impossible pattern）。
(menu_group
  name: (identifier) @name @item)

(menu_item
  name: (identifier) @name @item)

(toolbar_item
  name: (identifier) @name @item)

; 动作
(action_default_entry
  name: (name) @name @item)
