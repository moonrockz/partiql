///|
fn check_queries(cases : Array[(String, String)]) -> Unit raise {
  @expect.expect_all(soft => {
    for case in cases {
      soft
      .expect_call(() => statement_shape(case.0), label=case.0)
      .to_return()
      .to_equal(case.1)
    }
  })
}

///|
fn check_query_failures(sources : Array[String]) -> Unit raise {
  @expect.expect_all(soft => {
    for source in sources {
      soft
      .expect_call(() => @parser.parse_statement(source), label=source)
      .to_raise_matching(syntax_error, description="Syntax")
    }
  })
}

///|
test "projections" {
  check_queries([
    ("SELECT * FROM t", "(select * (from t))"),
    ("SELECT VALUE x FROM t", "(select (value x) (from t))"),
    ("SELECT a, b AS c, d e FROM t", "(select a, b as c, d as e (from t))"),
    ("SELECT t.* FROM t", "(select t.* (from t))"),
    ("SELECT DISTINCT a FROM t", "(select distinct a (from t))"),
    ("SELECT ALL a FROM t", "(select all a (from t))"),
    ("SELECT a DATA", "(select a as DATA)"),
    (
      "SELECT event.id WHERE event.id > 1", "(select (path event .id) (where (> (path event .id) 1)))",
    ),
    ("PIVOT v AT k FROM t", "(select (pivot v k) (from t))"),
    ("SELECT 1;", "(select 1)"),
  ])
  check_query_failures([
    "SELECT FROM t", "SELECT a, FROM t", "SELECT ()", "SELECT a b data", "SELECT a AS true",
    "SELECT *, *", "SELECT *, foo.*", "SELECT 1, *", "PIVOT v FROM data", "VALUE 1",
    "SELECT a FROM t;;", "SELECT a FROM t; b",
  ])
}

///|
test "FROM sources and joins" {
  check_queries([
    ("SELECT * FROM t AS v AT o BY u", "(select * (from t as v at o by u))"),
    ("SELECT * FROM t v", "(select * (from t as v))"),
    (
      "SELECT * FROM UNPIVOT x AS v AT k", "(select * (from (unpivot x as v at k)))",
    ),
    ("SELECT * FROM a, b", "(select * (from (, a b)))"),
    ("SELECT * FROM a CROSS JOIN b", "(select * (from (inner-cross a b)))"),
    ("SELECT * FROM a LEFT CROSS JOIN b", "(select * (from (left-cross a b)))"),
    (
      "SELECT * FROM a RIGHT OUTER CROSS JOIN b", "(select * (from (right-cross a b)))",
    ),
    ("SELECT * FROM a JOIN b ON x", "(select * (from (inner a b (on x))))"),
    (
      "SELECT * FROM a LEFT OUTER JOIN b ON x", "(select * (from (left a b (on x))))",
    ),
    ("SELECT * FROM a FULL JOIN b ON x", "(select * (from (full a b (on x))))"),
    (
      "SELECT * FROM a INNER JOIN (b INNER JOIN c ON y) ON x", "(select * (from (inner a (inner b c (on y)) (on x))))",
    ),
    (
      "SELECT * FROM (SELECT x FROM t) AS s", "(select * (from (select x (from t)) as s))",
    ),
    ("SELECT * FROM <<1, 2>> AS v", "(select * (from <<1 2>> as v))"),
  ])
  check_query_failures([
    "SELECT * FROM a CROSS JOIN b ON x", "SELECT * FROM a JOIN b", "SELECT * FROM a INNER JOIN b",
    "SELECT * FROM a LEFT JOIN b", "SELECT * FROM t AT o AS v", "SELECT * FROM",
  ])
}

///|
test "clauses" {
  check_queries([
    (
      "SELECT a FROM t LET a + 1 AS b WHERE b > 1", "(select a (from t) (let (+ a 1) b) (where (> b 1)))",
    ),
    (
      "SELECT k FROM t GROUP BY a AS k, b GROUP AS g HAVING COUNT(*) > 1", "(select k (from t) (group a as k, b group-as g) (having (> (call COUNT *) 1)))",
    ),
    (
      "SELECT k FROM t GROUP PARTIAL BY a", "(select k (from t) (group partial a))",
    ),
    (
      "SELECT a FROM data HAVING a > 1", "(select a (from data) (having (> a 1)))",
    ),
    (
      "SELECT a FROM t ORDER BY a DESC NULLS FIRST, b LIMIT 1 OFFSET 2", "(query (select a (from t)) (order a desc nulls-first, b) (limit 1) (offset 2))",
    ),
  ])
  check_query_failures([
    "SELECT a FROM t ORDER foo", "SELECT a FROM t ORDER BY", "SELECT a FROM t ORDER BY foo bar",
    "SELECT a FROM t ORDER BY foo, ,", "SELECT a FROM t ORDER BY a ASC DESC", "SELECT a FROM t ORDER BY a NULLS",
    "SELECT a FROM t ORDER BY a ASC FIRST", "SELECT a FROM t OFFSET 5 LIMIT 10",
    "SELECT a FROM t LIMIT 1 ORDER BY a", "SELECT a FROM t OFFSET SELECT",
  ])
}

///|
test "set operations, WITH and VALUES" {
  check_queries([
    (
      "SELECT a FROM t UNION SELECT b FROM u", "(union (select a (from t)) (select b (from u)))",
    ),
    (
      "SELECT a FROM t UNION ALL SELECT b FROM u INTERSECT SELECT c FROM v", "(union-all (select a (from t)) (intersect (select b (from u)) (select c (from v))))",
    ),
    ("a OUTER EXCEPT DISTINCT b", "(outer-except-distinct a b)"),
    (
      "(SELECT a FROM t ORDER BY a LIMIT 1) UNION (SELECT b FROM u) ORDER BY 1",
      "(query (union (query (select a (from t)) (order a) (limit 1)) (select b (from u))) (order 1))",
    ),
    (
      "WITH x AS (SELECT a FROM t) SELECT * FROM x", "(query (with x (select a (from t))) (select * (from x)))",
    ),
    ("VALUES (1, 2), (3, 4)", "(values (row 1 2) (row 3 4))"),
    (
      "SELECT * FROM t WHERE (a, b) IN (VALUES (1, 2))", "(select * (from t) (where (in (row a b) (values (row 1 2)))))",
    ),
    ("1 + 1", "(+ 1 1)"),
    ("((SELECT 1))", "(select 1)"),
  ])
  check_query_failures([
    "(1;)", "SELECT a FROM t UNION", "VALUES 1,2)", "WITH x AS SELECT 1",
  ])
}
