; Genero BDL (.4gl / .global) — syntax highlights for Zed
;
; 与 VSCode 侧 syntaxes/bdl.tmLanguage.json 语义对齐：
; 那个文件由 bdl-lsp/scripts/generate-tm-grammars.mjs 从同一份 grammar 源码
; 生成关键字表，这里的节点名与关键字都直接取自 src/node-types.json，
; 两边漂移时以 grammar 为准。
;
; 关于顺序：Zed 的 highlights.scm 是"后匹配的优先"（同 TextMate 相反），
; 所以更具体的规则要写在后面。这里按 [通用 → 具体] 组织。

; ---------------------------------------------------------------------------
; 注释 / 字符串 / 数字 / 布尔
; ---------------------------------------------------------------------------
(comment) @comment

(string) @string
(number) @number
(boolean) @boolean

; ---------------------------------------------------------------------------
; 预处理指令（#include / #define …）
; ---------------------------------------------------------------------------
(preproc) @preproc
(preproc_directive) @preproc

; ---------------------------------------------------------------------------
; 运算符
; ---------------------------------------------------------------------------
; 运算符 token 以 grammar 的匿名 token 为准。
; BDL 里没有 <> / != / >= / <= / || / ** 这类复合符号，
; 它们的语义由 AND/OR/NOT/IS 之类的关键字表达。
[
  "+"
  "-"
  "*"
  "/"
  ">"
  "<"
  "="
  ":"
  "|"
  "&&"
  "!"
] @operator

; ---------------------------------------------------------------------------
; 标点
; ---------------------------------------------------------------------------
["(" ")" "[" "]"] @punctuation.bracket
["," ";" "."] @punctuation.delimiter

; ---------------------------------------------------------------------------
; 类型
; ---------------------------------------------------------------------------
(basic) @type.builtin

; DATETIME YEAR TO FRACTION(3) 这类限定词
(datetime) @type.builtin

; RECORD LIKE table.* / DEFINE r RECORD
(record
  table: (identifier) @type)

(like
  table: (identifier) @type)

(like
  column: (identifier) @type)

(user_type) @type

; ---------------------------------------------------------------------------
; 函数 / 报表 / 标签 / MAIN
; ---------------------------------------------------------------------------
(function
  name: (identifier) @function)

(report
  name: (identifier) @function)

(call
  name: (variable
    (identifier) @function.call))

(label
  name: (identifier) @label)

; ---------------------------------------------------------------------------
; 变量
; ---------------------------------------------------------------------------
(variable
  (identifier) @variable)

; 参数位置：CALL f(a, b) / FUNCTION f(a, b) / REPORT r(a)
(call
  params: (expression
    (variable
      (identifier) @variable.parameter)))

(function
  params: (identifier) @variable.parameter)

(report
  params: (identifier) @variable.parameter)

; 记录字段访问：rec.field
(object
  property: (identifier) @property)

; ---------------------------------------------------------------------------
; 常量
; ---------------------------------------------------------------------------
; 常量的名字在隐藏规则里，用子节点匹配而不是字段匹配
(constant
  (identifier) @constant)

(builtin) @constant.builtin

; TRUE / FALSE
(boolean) @constant.builtin

; ---------------------------------------------------------------------------
; SQL 注入（见 injections.scm）
; ---------------------------------------------------------------------------
(sql_body) @embedded

; ---------------------------------------------------------------------------
; 关键字
;
; 分三类，粒度与 VSCode 侧的 scope 分组一致。
; Zed 的 capture 名以主题支持为准，@keyword 是最稳的兜底。
; ---------------------------------------------------------------------------

; 声明类
[
  "DEFINE"
  "CONSTANT"
  "TYPE"
  "RECORD"
  "ARRAY"
  "OF"
  "LIKE"
  "GLOBALS"
  "SCHEMA"
  "DATABASE"
  "IMPORT"
  "OPTIONS"
  "DIMENSION"
  "ATTRIBUTE"
  "ATTRIBUTES"
  "EXTERNAL"
  "DYNAMIC"
  "EXTEND"
  "INOUT"
  "OUT"
  "PRIVATE"
  "PUBLIC"
  "AS"
] @keyword

; 函数/报表骨架
[
  "MAIN"
  "FUNCTION"
  "REPORT"
  "RETURN"
  "RETURNING"
  "CALL"
] @keyword.function

; 控制流
[
  "IF"
  "THEN"
  "ELSE"
  "END"
  "CASE"
  "WHEN"
  "OTHERWISE"
  "WHILE"
  "FOR"
  "FOREACH"
  "CONTINUE"
  "EXIT"
  "GOTO"
  "RUN"
  "SLEEP"
  "LET"
  "INITIALIZE"
  "VALIDATE"
  "FREE"
  "LOCATE"
  "STEP"
  "NEXT"
  "PREVIOUS"
  "PRIOR"
  "FIRST"
  "LAST"
  "ABSOLUTE"
  "RELATIVE"
  "UP"
  "DOWN"
  "TRY"
  "CATCH"
  "RAISE"
  "WHENEVER"
  "DEFER"
] @keyword.control

; 交互语句
[
  "DISPLAY"
  "INPUT"
  "MENU"
  "CONSTRUCT"
  "PROMPT"
  "DIALOG"
  "MESSAGE"
  "ERROR"
  "WARNING"
  "SHOW"
  "HELP"
  "OPEN"
  "CLOSE"
  "CLEAR"
  "WINDOW"
  "SCREEN"
  "FORM"
  "FIELD"
  "COMMAND"
  "KEY"
  "ACCEPT"
  "CANCEL"
  "QUIT"
  "HIDE"
  "OPTION"
  "NAME"
  "INFIELD"
  "UNBUFFERED"
  "LABEL"
  "AT"
  "ROW"
  "ROWS"
  "SCROLL"
  "MAXCOUNT"
  "INSERT"
  "DELETE"
  "APPEND"
] @keyword

; 报表
[
  "START"
  "FINISH"
  "TERMINATE"
  "OUTPUT"
  "PRINT"
  "PRINTX"
  "SKIP"
  "PAUSE"
  "NEED"
  "EVERY"
  "PAGE"
  "TOP"
  "BOTTOM"
  "LEFT"
  "RIGHT"
  "MARGIN"
  "HEADER"
  "TRAILER"
  "GROUP"
  "ORDER"
  "BY"
  "ASC"
  "DESC"
  "COUNT"
  "WHERE"
  "PRINTER"
  "DESTINATION"
  "PIPE"
  "FORMAT"
  "LINE"
  "LINES"
  "COLUMN"
  "COLUMNS"
  "SPACE"
  "SPACES"
  "DELIMITER"
] @keyword

; SQL 与事务
[
  "SELECT"
  "UPDATE"
  "DELETE"
  "INSERT"
  "CREATE"
  "ALTER"
  "DROP"
  "TRUNCATE"
  "RENAME"
  "UNLOAD"
  "LOAD"
  "FETCH"
  "DECLARE"
  "PUT"
  "FLUSH"
  "CURSOR"
  "PREPARE"
  "EXECUTE"
  "USING"
  "INTO"
  "FROM"
  "BEGIN"
  "WORK"
  "COMMIT"
  "ROLLBACK"
  "SAVEPOINT"
  "RELEASE"
  "IMMEDIATE"
  "EXCLUSIVE"
  "LOCK"
  "LOCKS"
  "UNLOCK"
  "ISOLATION"
  "TRANSACTION"
  "COMMITTED"
  "REPEATABLE"
  "READ"
  "WAIT"
  "WAITING"
  "SQLERROR"
  "FOUND"
  "SQL"
  "REOPTIMIZATION"
  "STABILITY"
] @keyword

; 事件钩子
[
  "BEFORE"
  "AFTER"
  "ON"
  "CHANGE"
  "ACTION"
  "IDLE"
  "EXPAND"
  "COLLAPSE"
  "DRAG_START"
  "DRAG_FINISHED"
  "DRAG_ENTER"
  "DRAG_OVER"
  "DROP"
  "FILL"
  "BUFFER"
  "TERMINATE"
  "SIGNAL"
  "INTERRUPT"
  "CURRENT"
] @keyword

; 逻辑 / 比较
[
  "AND"
  "OR"
  "NOT"
  "IS"
  "NULL"
  "ANY"
  "MATCHES"
] @keyword.operator

; 显示属性（COLOR=、BORDER …）
[
  "BLACK"
  "BLUE"
  "CYAN"
  "GREEN"
  "MAGENTA"
  "RED"
  "WHITE"
  "YELLOW"
  "BOLD"
  "UNDERLINE"
  "BLINK"
  "REVERSE"
  "NORMAL"
  "INVISIBLE"
  "CLIPPED"
  "WORDWRAP"
  "WRAP"
  "NO"
  "STYLE"
  "TEXT"
  "IMAGE"
  "COMMENT"
  "BORDER"
  "AUTO"
  "TO"
  "WITH"
  "WITHOUT"
  "DEFAULTS"
  "IN"
  "OFF"
  "MOD"
  "PROGRAM"
  "USER"
] @keyword

; 时间单位
[
  "YEAR"
  "MONTH"
  "DAY"
  "HOUR"
  "MINUTE"
  "SECOND"
  "FRACTION"
  "TODAY"
  "DATE"
  "DATETIME"
  "INTERVAL"
  "CURRENT"
] @keyword

; 类型关键字（与 (basic) 节点重叠时，节点规则优先）
[
  "CHAR"
  "CHARACTER"
  "VARCHAR"
  "STRING"
  "TEXT"
  "BYTE"
  "INTEGER"
  "SMALLINT"
  "BIGINT"
  "TINYINT"
  "DECIMAL"
  "DEC"
  "MONEY"
  "FLOAT"
  "SMALLFLOAT"
  "BOOLEAN"
  "SEQUENCE"
  "TABLE"
  "INDEX"
  "XML"
  "ASCII"
  "UNITS"
  "LENGTH"
  "ESCAPE"
  "NULL"
] @type.builtin

; 其它杂项
[
  "AT"
  "DORMANT"
  "EXPLAIN"
  "FILE"
  "HANDLER"
  "HOLD"
  "JAVA"
  "KEEP"
  "MEMORY"
  "MODE"
  "QUIT"
  "RETAIN"
  "SHORT"
  "STOP"
  "THROUGH"
  "THRU"
  "TRUE"
  "FALSE"
  "UNCONSTRAINED"
  "CONSTRAINED"
  "UNIQUE"
  "VALIDATE"
  "FGL"
  "WITH"
  ; 连接/描述类（DESCRIBE / CONNECT / CONNECTION / DISCONNECT / CONCURRENT）
  "DESCRIBE"
  "CONNECT"
  "CONNECTION"
  "CONCURRENT"
  "DISCONNECT"
  ; 其它
  "APPLICATION"
  "CIRCUIT"
  "DIM"
  "DIRTY"
  "SET"
] @keyword
