; Genero BDL — outline
;
; 只列有"导航价值"的节点：函数、报表、MAIN、类型/记录、标签。
; 变量不放进大纲——一个 7000 行的模块能有几百个 DEFINE，会把大纲淹掉。
;
; 缩进说明：Zed 用 @context 表达层级，没有 context 的条目是平的。
;
; ── 关于 @item 的一个必须遵守的约束（P7-A-1）────────────────────────────
;
; Zed 用 @item 的**区间**构建大纲的父子关系。若同一份 query 产出两个区间
; 完全相同的 @item，Zed 会把后一个当成前一个的子节点，大纲出现假层级。
;
; grammar 里"一条语句声明多个名字"是**单个节点带多个 name: 字段**：
;
;   (define
;     name: (identifier)      ← 第 1 个变量
;     types: (types ...)
;     name: (identifier)      ← 第 2 个变量
;     types: (types ...))
;
; 所以 **@item 必须绑在名字节点本身，不能绑在整条语句上**：
;
;   ✗ (define name: (identifier) @name) @item    → 两个变量区间相同，假层级
;   ✓ (define name: (identifier) @name @item)    → 每个变量区间独立
;
; tests/verify-queries.mjs 有断言守着这条规则（"@item 区间两两不同"），
; 改这里之前先看那段断言的注释。

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
; @item 与 @name 绑同一个节点：一条 CONSTANT 可声明多个常量，
; 绑整条语句会让这些常量的 @item 区间完全相同（见文件头说明）。
(constant
  (identifier) @name @item)

; TYPE 定义（一条 TYPE 可声明多个名字，同样绑到 identifier）
(type
  name: (identifier) @name @item)

; 全局变量（模块级 DEFINE，数量有限）
; 一条 DEFINE 可声明多个变量，@item 必须绑到 identifier（见文件头说明）。
(define
  name: (identifier) @name @item)

; 交互语句：菜单标题便于在大模块里定位界面逻辑
(menu) @item

(dialog) @item
