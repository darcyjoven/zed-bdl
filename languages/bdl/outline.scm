; Genero BDL — outline
;
; 列出：函数、报表、MAIN、类型/记录、常量、标签，以及变量。
; 变量分两层：模块级变量在顶层，函数内变量归属所属函数（可折叠）。
;
; ══ 条目模型（容器 + 叶子）══════════════════════════════════════════════
;
; 条目分两类，@item 的绑法**相反**：
;
;   容器（函数/报表/MAIN/MENU/DIALOG）：@item 绑**整个节点**，
;     @name 绑名字/标题。函数内声明的变量、内层 MENU 因此成为它的
;     子级——可以在大纲里折叠（用户 2026-10-21 明确要求此行为）。
;
;   叶子（DEFINE/TYPE/CONSTANT/LABEL）：@item 绑**名字 identifier**，
;     与 @name 同节点。同一条语句声明的多个名字（DEFINE i,j INTEGER）
;     区间互不重叠，互为兄弟——绝不允许互相嵌套。
;
; 为什么容器不能把 @item 绑到名字上：那样函数体内部的条目无法归到
; 函数下，全部与函数平级（1ee95bf 犯的错，2026-10-21 被用户指出）。
;
; 为什么叶子不能把 @item 绑到整条语句上：一条语句声明多个名字时，
; 各名字产出**区间完全相同**的 item，按 Zed 的判据后者成为前者的子级
; （DEFINE i,j INTEGER 会出现 j 挂在 i 下——最初报的 bug）。
;
; 这套模型与 Zed 内置语言一致：Rust/Python 的 outline.scm 里函数的
; @item 同样覆盖整块（见 crates/grammars/src/<lang>/outline.scm）。
; "父 item 覆盖子 item 区间"是合法的层级表达，不是 bug。
;
; ── Zed 的层级判据（crates/language/src/buffer.rs）────────────────────
;
;     items.sort_by_key(|item| (item.range.start, Reverse(item.range.end)));
;     for item in items {
;         while 栈顶.end < item.end { pop }
;         depth = 栈长;
;         push(item.end);
;     }
;
; 即"前一条目结束位置 ≥ 当前条目结束位置"就算父子（区间相交即嵌套）。
;
; ── 断言 ──
;
; tests/verify-queries.mjs 复刻了上述算法，并检查三条不变量：
;   ① 同一文件内所有 @item 区间两两不同
;      （否则同语句多名字互相嵌套）
;   ② 叶子的父级不能是叶子
;   ③ 容器内部的每个变量，其 Zed 父级链上必须能找到该容器
;      （① ② 都无法区分"函数容器"与"变量叶子"——它们都是单行短标识符。
;        ③ 以 tree-sitter parse 的语法树为独立真相源，才抓得住 1ee95bf
;        那种"把函数 @item 缩到名字节点"的回归。）
;
; 7699 个真实 .4gl + 7409 个 .per 语料扫描：0 处假层级。

; ── 容器 ──────────────────────────────────────────────────────────────

; 函数：item 覆盖整个函数，内部变量/菜单成为子级（可折叠）。
(function
  name: (identifier) @name) @item

; 报表：同函数。
(report
  name: (identifier) @name) @item

; MAIN：没有名字节点，用锚点 "." 只取开头的 MAIN 关键字当名字
; （否则会连 END MENU/END FUNCTION 式的结尾关键字一起匹配）。
(main
  . "MAIN" @name) @item

; 菜单：title 可选（rule/interface.js 的 _menu_head）。
; 有标题 → 标题作名字；无标题 → 只有 item。两条规则用 !title 互斥，
; 不会重复匹配。嵌套 MENU 的内层归外层之下。
(menu
  title: (_) @name) @item

(menu !title) @item

; 对话框：无 title 字段（rule/interface.js 的 dialog）。
(dialog) @item

; ── 叶子 ──────────────────────────────────────────────────────────────

; 标签（GOTO 目标）
(label
  name: (identifier) @name @item)

; 常量（name 字段来自隐藏规则，只能按子节点匹配）
(constant
  (identifier) @name @item)

; TYPE 定义
(type
  name: (identifier) @name @item)

; 变量（模块级与函数内都收；函数内的会自动归到所属函数下）
(define
  name: (identifier) @name @item)
