; Genero BDL — bracket matching
;
; 只声明 grammar 里真实存在的括号 token。
; BDL 的 { } 是块注释，不是结构括号，grammar 也没有对应 token，
; 写进来会让整份 query 编译失败。
("(" @open ")" @close)
("[" @open "]" @close)
