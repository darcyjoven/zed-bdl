-- 高亮样例：覆盖注释/字符串/数字/布尔/类型/函数/变量/字段/SQL/预处理
#include "globals.4gl"

SCHEMA ds

GLOBALS
  DEFINE g_counter INTEGER
  DEFINE g_name CHAR(30)
END GLOBALS

CONSTANT c_max = 100
CONSTANT c_flag = TRUE

TYPE t_row RECORD
  id LIKE customer.id,
  name CHAR(50),
  amount DECIMAL(10,2)
END RECORD

PRIVATE DEFINE arr ARRAY[10] OF INTEGER

FUNCTION f_compute(p_x, p_y)
  DEFINE r INTEGER
  LET r = p_x + p_y * 2
  RETURN r
END FUNCTION

MAIN
  DEFINE n INTEGER
  DEFINE s STRING
  DEFINE rec t_row

  LET n = f_compute(1, 2)
  LET s = "hello" || "world"

  IF n > 0 THEN
    DISPLAY "positive"
  ELSE
    DISPLAY "non-positive"
  END IF

  CASE n
    WHEN 1
      DISPLAY "one"
    OTHERWISE
      DISPLAY "many"
  END CASE

  WHILE n < 10
    LET n = n + 1
  END WHILE

  FOR n = 1 TO 10 STEP 2
    DISPLAY n
  END FOR

  LET rec.id = 42
  LET rec.name = "x"

  SELECT COUNT(*) INTO n FROM customer WHERE id = rec.id
  DISPLAY rec.id, rec.name
END MAIN

REPORT r_list(p_start)
  DEFINE p_start INTEGER
  OUTPUT
    TOP MARGIN 2
  FORMAT
    PAGE HEADER
      PRINTX "header"
    ON EVERY ROW
      PRINTX p_start
END REPORT
