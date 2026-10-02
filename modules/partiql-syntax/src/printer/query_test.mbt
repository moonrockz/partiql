///|
test "select clauses" {
  check_prints([
    ("select a, b as c, d e from t", "SELECT a, b AS c, d AS e FROM t"),
    ("SELECT * FROM t", "SELECT * FROM t"),
    ("SELECT DISTINCT a FROM t", "SELECT DISTINCT a FROM t"),
    ("SELECT ALL a FROM t", "SELECT ALL a FROM t"),
    ("SELECT VALUE {'a': x} FROM t", "SELECT VALUE {'a': x} FROM t"),
    ("SELECT t.*, u.a FROM t, u", "SELECT t.*, u.a FROM t, u"),
    ("SELECT (a + b).* FROM t", "SELECT (a + b).* FROM t"),
    ("PIVOT v AT k FROM t", "PIVOT v AT k FROM t"),
    ("SELECT 1", "SELECT 1"),
    (
      "SELECT a FROM t LET a + 1 AS b, 2 AS c WHERE b > 1", "SELECT a FROM t LET a + 1 AS b, 2 AS c WHERE b > 1",
    ),
    (
      "SELECT k, count(*) FROM t GROUP BY a AS k, b GROUP AS g HAVING count(*) > 1",
      "SELECT k, count(*) FROM t GROUP BY a AS k, b GROUP AS g HAVING count(*) > 1",
    ),
    ("SELECT x FROM t GROUP PARTIAL BY x", "SELECT x FROM t GROUP PARTIAL BY x"),
    (
      "SELECT VALUE g FROM t GROUP ALL AS g", "SELECT VALUE g FROM t GROUP ALL AS g",
    ),
    (
      "SELECT a FROM t ORDER BY a DESC NULLS LAST, b LIMIT 10 OFFSET 5", "SELECT a FROM t ORDER BY a DESC NULLS LAST, b LIMIT 10 OFFSET 5",
    ),
    (
      "WITH x AS (SELECT a FROM t) SELECT * FROM x", "WITH x AS (SELECT a FROM t) SELECT * FROM x",
    ),
    ("TABLE hr.employees", "TABLE hr.employees"),
    ("VALUES (1, 2), (3)", "VALUES (1, 2), (3)"),
    (
      "SELECT a FROM (SELECT a FROM t) AS s", "SELECT a FROM (SELECT a FROM t) AS s",
    ),
    ("f((SELECT a FROM t))", "f(SELECT a FROM t)"),
    ("x IN (SELECT a FROM t)", "x IN (SELECT a FROM t)"),
    ("[(VALUES (1)), 2]", "[(VALUES (1)), 2]"),
  ])
}

///|
test "from items and joins" {
  check_prints([
    ("SELECT * FROM t AS x AT i BY b", "SELECT * FROM t AS x AT i BY b"),
    ("SELECT * FROM t x", "SELECT * FROM t AS x"),
    ("SELECT * FROM c, LATERAL c.o AS o", "SELECT * FROM c, LATERAL c.o AS o"),
    ("SELECT * FROM UNPIVOT t AS v AT k", "SELECT * FROM UNPIVOT t AS v AT k"),
    ("SELECT * FROM a INNER JOIN b ON x", "SELECT * FROM a JOIN b ON x"),
    (
      "SELECT * FROM a LEFT OUTER JOIN b ON x", "SELECT * FROM a LEFT JOIN b ON x",
    ),
    (
      "SELECT * FROM a RIGHT JOIN b ON x FULL JOIN c ON y", "SELECT * FROM a RIGHT JOIN b ON x FULL JOIN c ON y",
    ),
    ("SELECT * FROM a CROSS JOIN b", "SELECT * FROM a CROSS JOIN b"),
    ("SELECT * FROM a LEFT CROSS JOIN b", "SELECT * FROM a LEFT CROSS JOIN b"),
    (
      "SELECT * FROM a JOIN (b JOIN c ON y) ON x", "SELECT * FROM a JOIN (b JOIN c ON y) ON x",
    ),
    ("SELECT * FROM (a, b) JOIN c ON x", "SELECT * FROM (a, b) JOIN c ON x"),
    ("SELECT * FROM a, b JOIN c ON x", "SELECT * FROM a, b JOIN c ON x"),
  ])
}

///|
test "set operations" {
  check_prints([
    (
      "SELECT a FROM t UNION SELECT b FROM u", "SELECT a FROM t UNION SELECT b FROM u",
    ),
    ("a UNION ALL b EXCEPT DISTINCT c", "a UNION ALL b EXCEPT DISTINCT c"),
    ("a UNION b INTERSECT c", "a UNION b INTERSECT c"),
    (
      "(SELECT a FROM t UNION SELECT b FROM u) INTERSECT SELECT c FROM v", "(SELECT a FROM t UNION SELECT b FROM u) INTERSECT SELECT c FROM v",
    ),
    (
      "SELECT a FROM t UNION (SELECT b FROM u UNION SELECT c FROM v)", "SELECT a FROM t UNION (SELECT b FROM u UNION SELECT c FROM v)",
    ),
    ("a OUTER UNION CORRESPONDING b", "a OUTER UNION CORRESPONDING b"),
    (
      "TABLE a UNION ALL CORRESPONDING BY (name, title) TABLE b", "TABLE a UNION ALL CORRESPONDING BY (name, title) TABLE b",
    ),
    (
      "(SELECT a FROM t LIMIT 1) UNION SELECT b FROM u", "(SELECT a FROM t LIMIT 1) UNION SELECT b FROM u",
    ),
    (
      "SELECT a FROM t UNION SELECT b FROM u ORDER BY 1", "SELECT a FROM t UNION SELECT b FROM u ORDER BY 1",
    ),
    (
      "((SELECT a FROM t LIMIT 1) UNION (SELECT b FROM u)) ORDER BY 1", "(SELECT a FROM t LIMIT 1) UNION SELECT b FROM u ORDER BY 1",
    ),
  ])
}
