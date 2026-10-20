; Genero BDL — outline
;
; 只列有"导航价值"的节点：函数、报表、MAIN、类型/记录、标签。
; 变量不放进大纲——一个 7000 行的模块能有几百个 DEFINE，会把大纲淹掉。
;
; 缩进说明：Zed 用 @context 表达层级，没有 context 的条目是平的。

; 函数
(function
  name: (identifier) @name) @item

; 报表
(report
  name: (identifier) @name) @item

; MAIN（没有名字，用关键字本身作为名字）
(main) @item

; 标签（GOTO 目标）
(label
  name: (identifier) @name) @item

; 常量（name 字段来自隐藏规则，只能按子节点匹配）
(constant
  (identifier) @name) @item

; TYPE 定义
(type
  name: (identifier) @name) @item

; 全局变量（模块级 DEFINE，数量有限）
(define
  name: (identifier) @name) @item

; 交互语句：菜单标题便于在大模块里定位界面逻辑
(menu) @item

(dialog) @item
