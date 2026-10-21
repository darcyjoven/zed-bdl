-- outline 样例：覆盖大纲层级的全部关键结构。
--
-- ══ 背景 ═══════════════════════════════════════════════════════════════
--
-- 1) 一条 DEFINE 是**单个节点带多个 name: 字段**：
--      (define
--        name: (identifier)   ← 第 1 个变量
--        types: (types ...)
--        name: (identifier)   ← 第 2 个变量
--        types: (types ...))
--
--    若 outline.scm 把 @item 绑在整条语句上，两个变量会产出
--    **区间完全相同**的两个 match，Zed 按区间构建父子关系时
--    会把后一个判成前一个的子节点，大纲出现假层级（最初报的 bug）。
--
-- 2) Zed 的层级判据是"区间相交"，不是"区间相同"：
--      items.sort_by_key(|item| (item.range.start, Reverse(item.range.end)));
--      栈里保存每个条目的 end；当前条目的 end ≥ 栈顶 end 时，
--      栈顶就是当前条目的父级。
--
-- ══ 期望的层级模型（容器 + 叶子）═════════════════════════════════════
--
--   容器（函数/报表/MAIN/MENU/DIALOG）：@item 绑**整个节点**。
--     函数内部声明的变量因此成为它的子级——可以折叠。
--
--   叶子（DEFINE/TYPE/CONSTANT/LABEL）：@item 绑**名字 identifier**。
--     同一条语句声明的多个名字区间互不重叠，互为兄弟。
--
-- 因此本文件期望：
--   · f_outline / f_single / r_outline / MAIN 是顶层条目
--   · 函数内的 l_local1 / l_local2 / l_single 等变量是**函数的子级**
--   · l_local1 与 l_local2（同一条 DEFINE）**互为兄弟**，不嵌套
--   · l_single（独立的一条 DEFINE）与 l_local1 也**互为兄弟**
--
-- 本文件用于 verify-queries.mjs 的三条断言：
--   ① @item 区间两两不同
--   ② 叶子的父级不能是叶子
--   ③ 容器内部的变量必须归属该容器（父级链上能找到容器）

SCHEMA ds

-- ── 模块级：多变量 DEFINE ───────────────────────────────────────────

-- 两变量、两类型
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

-- ── 模块级：多 CONSTANT ──────────────────────────────────────────────

CONSTANT c_one = 1,
         c_two = 2,
         c_three = 3

-- ── 模块级：多 TYPE（一个 RECORD、一个标量）─────────────────────────

TYPE t_a RECORD
       x INTEGER
     END RECORD,
     t_b STRING

-- ── 函数：内部变量归属函数（可折叠），同一条 DEFINE 的变量互为兄弟 ──
--
-- 这三种写法都要覆盖：
--   ① 函数内多变量 DEFINE（同一 name 字段组）
--   ② 函数内单变量 DEFINE
--   ③ 函数参数
--
-- 另外 ④：一条多变量 DEFINE 与一条独立 DEFINE 语句并存——
--   l_local1/l_local2（同一句）与 l_single（另一句）必须是**兄弟**，
--   不能出现 l_single 挂在 l_local2 下面之类的假层级。
FUNCTION f_outline(p_arg)
  DEFINE l_local1 INTEGER,
         l_local2 STRING
  DEFINE l_single CHAR(10)
  DEFINE l_third1 INTEGER,
         l_third2 INTEGER
  LET l_local1 = p_arg
  RETURN l_local1
END FUNCTION

FUNCTION f_single(p_one)
  DEFINE l_only INTEGER
  LET l_only = p_one
  RETURN l_only
END FUNCTION

-- ── MAIN：块内变量归属 MAIN ──────────────────────────────────────────
-- main 节点没有名字子节点，用锚点 "." 匹配开头的 MAIN 关键字。
MAIN
  DEFINE m_one INTEGER,
         m_two STRING
  DEFINE m_three CHAR(5)
  LET m_one = f_outline(1)
  DISPLAY m_one, m_two, m_three
END MAIN

-- ── 报表：报表内变量归属报表 ────────────────────────────────────────
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
