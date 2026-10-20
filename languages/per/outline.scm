; Genero Form — outline
;
; .per 的大纲按小节组织：LAYOUT / TABLES / ATTRIBUTES / INSTRUCTIONS …
; 每个 item 定义都进大纲，方便在表单里快速跳到某个字段。

; item 定义：EDIT f01 = ...
(attribute_item
  tag: (name) @name) @item

(untyped_attribute_item
  tag: (identifier) @name) @item

(phantom_item
  (field_ref
    (name) @name)) @item

; SCREEN RECORD
(screen_record_entry
  name: (name) @name) @item

; 表
(table_entry
  (identifier) @name) @item

; 菜单：name 字段在 grammar 里是 `identifier | 关键字` 的联合，
; 直接绑 identifier 才合法（绑 (name) 会报 Impossible pattern）。
(menu_group
  name: (identifier) @name) @item

(menu_item
  name: (identifier) @name) @item

(toolbar_item
  name: (identifier) @name) @item

; 动作
(action_default_entry
  name: (name) @name) @item
