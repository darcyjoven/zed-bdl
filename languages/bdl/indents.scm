; Genero BDL — indentation
;
; 设计原则：只用"块结构"驱动缩进，不用行尾字符启发式。
; BDL 的 IF/WHILE/FOR 都以关键字结尾（THEN / 条件 / 表达式），
; 靠行尾判断会漏；靠节点判断才准。
;
; @indent  整段缩进（节点首行到末行）
; @start   缩进范围从该节点**结束**处开始
; @end     缩进范围到该节点**开始**处结束
; @outdent 在节点开始处减少一级

; ---------------------------------------------------------------------------
; 流程控制块
; ---------------------------------------------------------------------------

; IF ... THEN ... [ELSE ...] END IF
; ELSE 要跟 IF 对齐，因此用 @outdent 把它拉回来
(if) @indent
(if
  "THEN" @start)
(if
  (else) @outdent)

; CASE ... WHEN ... OTHERWISE ... END CASE
(case) @indent
(case
  (when) @outdent)
(case
  (otherwise) @outdent)

; WHILE / FOR / FOREACH
(while) @indent
(while
  condition: (_) @end)

(for) @indent
(for
  step: (_)? @end)

(foreach) @indent
(foreach
  (variable) @end)

; TRY / CATCH
(try) @indent
(try
  (catch) @outdent)

; ---------------------------------------------------------------------------
; 函数 / 报表 / MAIN
; ---------------------------------------------------------------------------

; MAIN 与 FUNCTION 的体缩进，END MAIN / END FUNCTION 回到顶层
(main) @indent

(function) @indent
(function
  name: (identifier) @end)

(report) @indent
(report
  name: (identifier) @end)

; ---------------------------------------------------------------------------
; 交互块
; ---------------------------------------------------------------------------

(display) @indent
(input) @indent
(construct) @indent
(menu) @indent
(dialog) @indent
(prompt) @indent

; ON ACTION / BEFORE FIELD 之类的分支体
(branch) @indent

; ---------------------------------------------------------------------------
; 声明块
; ---------------------------------------------------------------------------

; DEFINE r RECORD ... END RECORD
(record) @indent

; GLOBALS 段
(globals) @indent

; BEGIN ... END（事务块）
(begin) @indent

; ---------------------------------------------------------------------------
; 括号
; ---------------------------------------------------------------------------
"(" @indent
")" @outdent
"[" @indent
"]" @outdent
