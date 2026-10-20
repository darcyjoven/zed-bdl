; Genero BDL — SQL 注入
;
; `.4gl` 里的 SELECT/INSERT/UPDATE/DELETE 块在 grammar 里是 (sql_body)，
; 把它的内容标记成 SQL 语言，Zed 就会用 SQL 的 highlights.scm 再着一次色。
;
; 注意：注入的是**语法高亮**，不改变 LSP 的解析结果。bdl-lsp 仍然
; 按 BDL 处理整份文件，诊断/跳转不受影响。

(sql_body) @injection.content
(#set! injection.language "sql")
