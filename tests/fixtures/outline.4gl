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

-- 交互语句与函数，供其他规则命中
FUNCTION f_outline(p_arg)
  DEFINE l_local1 INTEGER,
         l_local2 STRING
  LET l_local1 = p_arg
  RETURN l_local1
END FUNCTION

MAIN
  DEFINE m_one INTEGER,
         m_two STRING
  LET m_one = f_outline(1)
  DISPLAY m_one, m_two
END MAIN

REPORT r_outline(p_start)
  DEFINE p_start INTEGER
  OUTPUT
    TOP MARGIN 2
  FORMAT
    ON EVERY ROW
      PRINTX p_start
END REPORT
