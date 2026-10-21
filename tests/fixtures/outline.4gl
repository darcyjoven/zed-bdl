-- outline 样例：专门覆盖"一条语句声明多个名字"的结构。
--
-- 背景（P7-A-1）：
--   grammar 里一条 DEFINE 是**单个节点带多个 name: 字段**：
--     (define
--       name: (identifier)   ← 第 1 个变量
--       types: (types ...)
--       name: (identifier)   ← 第 2 个变量
--       types: (types ...))
--
--   若 outline.scm 把 @item 绑在整条语句上，两个变量会产出
--   **区间完全相同**的两个 match，Zed 按区间构建父子关系时
--   会把后一个判成前一个的子节点，大纲出现假层级。
--
--   本文件用于 verify-queries.mjs 的"@item 区间必须两两不同"断言。
--   断言在旧 query 上必须失败，修复后必须通过。

SCHEMA ds

-- 模块级多变量 DEFINE（两变量、两类型）
DEFINE g_a LIKE type_file.chr20,
       g_b STRING

-- 三变量，类型各不相同
DEFINE g_c INTEGER,
       g_d DECIMAL(10,2),
       g_e CHAR(8)

-- 一个变量 RECORD、一个变量普通类型：结构最复杂的一种
DEFINE g_rec RECORD
         f1 INTEGER,
         f2 CHAR(20)
       END RECORD,
       g_plain INTEGER

-- PRIVATE 作用域前缀
PRIVATE DEFINE g_priv1 INTEGER,
              g_priv2 STRING

-- 多 CONSTANT
CONSTANT c_one = 1,
         c_two = 2,
         c_three = 3

-- 多 TYPE（一个 RECORD、一个标量）
TYPE t_a RECORD
       x INTEGER
     END RECORD,
     t_b STRING

-- 函数：内部变量必须与函数名平级，不能变成子级。
--
-- 这正是 P7-B-3 的根因：若 (function ...) @item 绑在整个函数体上，
-- 函数内部的 DEFINE 变量的 item 落在函数区间内，
-- 按 Zed 的 depth 算法（"前一条目结束位置 >= 当前条目结束位置"即判为子级）
-- 它们会被判成函数的子级。
--
-- 这三种写法都要覆盖：
--   ① 函数内多变量 DEFINE（同一 name 字段组）
--   ② 函数内单变量 DEFINE
--   ③ 函数参数
FUNCTION f_outline(p_arg)
  DEFINE l_local1 INTEGER,
         l_local2 STRING
  DEFINE l_single CHAR(10)
  LET l_local1 = p_arg
  RETURN l_local1
END FUNCTION

FUNCTION f_single(p_one)
  DEFINE l_only INTEGER
  LET l_only = p_one
  RETURN l_only
END FUNCTION

-- MAIN：块内变量必须与 MAIN 关键字平级。
-- main 节点没有名字子节点，用锚点 "." 匹配开头的 MAIN 关键字。
MAIN
  DEFINE m_one INTEGER,
         m_two STRING
  DEFINE m_three CHAR(5)
  LET m_one = f_outline(1)
  DISPLAY m_one, m_two, m_three
END MAIN

-- 报表：报表内变量必须与报表名平级。
REPORT r_outline(p_start)
  DEFINE p_start INTEGER
  DEFINE q_local INTEGER,
         q_local2 STRING
  OUTPUT
    TOP MARGIN 2
  FORMAT
    ON EVERY ROW
      PRINTX p_start
END REPORT
