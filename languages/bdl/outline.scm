; Genero BDL — outline
;
; 只列有"导航价值"的节点：函数、报表、MAIN、类型/记录、标签。
; 变量不放进大纲——一个 7000 行的模块能有几百个 DEFINE，会把大纲淹掉。
;
; 缩进说明：Zed 用 @context 表达层级，没有 context 的条目是平的。
;
; ══ @item 的区间规则（改这里之前务必读完）══════════════════════════════
;
; Zed 用 @item 的**区间**构建大纲的父子关系。源码
; crates/language/src/buffer.rs：
;
;     items.sort_by_key(|item| (item.range.start, Reverse(item.range.end)));
;     let mut item_ends_stack = Vec::<Point>::new();
;     for item in items {
;         while let Some(last_end) = item_ends_stack.last().copied() {
;             if last_end < item.range.end { item_ends_stack.pop(); } else { break; }
;         }
;         depth = item_ends_stack.len();
;         item_ends_stack.push(item.range.end);
;     }
;
; 翻译成人话：**只要前一个条目的结束位置不小于当前条目的结束位置，
; 当前条目就被判为它的子级**（Point = 行,列，按行优先比较）。
;
; 由此得出两条必须遵守的规则：
;
; 规则 1：@item 必须绑在**最小**的语义单元上，不能绑在包含它的父节点上。
;
;   反例（会导致假层级）：
;     (function name: (identifier) @name) @item
;   函数 item 的区间是**整个函数体**，函数内部声明的变量 item 落在
;   这个区间里 → 按上面的判据，它们全被判成函数的子级。
;   实测：120 个真实文件里 116 个出现层级，4051 个条目有层级。
;
;   正解：
;     (function name: (identifier) @name @item)
;   item 只覆盖函数名，函数体内部的东西与它区间不交 → 平级。
;
; 规则 2：一个语法节点里声明多个名字时（如 DEFINE a INT, b INT），
;   @item 必须绑在**每个名字**上，不能绑在整条语句上。
;
;   grammar 里一条 DEFINE 是单节点多 name: 字段：
;     (define
;       name: (identifier)      ← 第 1 个变量
;       types: (types ...)
;       name: (identifier)      ← 第 2 个变量
;       types: (types ...))
;
;   绑整条语句 → 两个变量产出区间完全相同的 item → 后者被判成前者的子级。
;
;   正解：
;     (define name: (identifier) @name @item)
;
; 规则 3：@item 与 @name 可以绑在同一个节点上——这正是我们要的
;   （显示文本取 @name，区间取 @item，两者同节点最省事）。
;
; ── 断言 ──
;
; tests/verify-queries.mjs 守着这些规则，见该文件里
; "大纲 @item 区间唯一性" 一节。它复刻了 Zed 的 depth 算法，
; 能直接算出某个文件里哪些条目会有层级。
;
; 规则 4（.per 专用）：PHANTOM table.column 的 field_ref 有两个 name
;   子节点（表名 + 列名），只写 (field_ref (name) @name) 会让两者
;   区间重合 → 必须绑 column: 字段。

; 函数
; @item 绑在函数名上（不是整个函数体）——见文件头规则 1。
(function
  name: (identifier) @name @item)

; 报表
; 同函数：item 只覆盖报表名，否则报表内的变量会变成子级。
(report
  name: (identifier) @name @item)

; MAIN（没有名字节点，用开头的 MAIN 关键字）
;
; 锚点 "." 表示"第一个子节点"，用来只匹配开头的 MAIN，
; 不匹配结尾的 END MAIN（否则会出现两条 MAIN 条目）。
; item 只覆盖 MAIN 关键字，MAIN 块内部声明的变量因此保持平级。
(main
  . "MAIN" @name @item)

; 标签（GOTO 目标）
(label
  name: (identifier) @name @item)

; 常量（name 字段来自隐藏规则，只能按子节点匹配）
; 一条 CONSTANT 可声明多个常量，@item 绑到每个 identifier 上。
(constant
  (identifier) @name @item)

; TYPE 定义（一条 TYPE 可声明多个名字，同样绑到 identifier）
(type
  name: (identifier) @name @item)

; 全局变量（模块级 DEFINE，数量有限）
; 一条 DEFINE 可声明多个变量，@item 绑到每个 identifier 上。
(define
  name: (identifier) @name @item)

; 菜单：抓菜单标题（title 字段），item 只覆盖标题本身。
;
; 为什么要分两条规则：
;   grammar 里 menu 的 title 是**可选**的（rule/interface.js 的 _menu_head）：
;     seq(kw("MENU"), optional(field("title", choice($.variable, $.string))), …)
;   所以要同时处理"有标题"和"无标题"两种情况，否则会出现重复条目。
;
;   !title 表示"该节点没有 title 字段"，与另一条规则互斥，不会重复匹配。
;
; 为什么 item 要绑标题而不是整个 menu 块：
;   嵌套菜单（外层 MENU 里套 MENU）时，整块 item 会包含内层 item，
;   按 Zed 的 depth 判据内层菜单会被判成子级（见文件头规则 1）。
;   绑标题后区间互不相交 → 全部平级。
[
  (menu title: (_) @name @item)
  (menu !title) @item
]

; 对话框：dialog 没有 title 字段（rule/interface.js），item 覆盖整个块。
; DIALOG 块内不声明变量，不会与子条目相交，实测无层级问题。
(dialog) @item
