///|
/// The canonical text of a statement.
fn canon(source : String) -> String raise {
  @printer.print(@parser.parse_statement(source))
}

///|
fn check_prints(cases : Array[(String, String)]) -> Unit raise {
  @expect.expect_all(soft => {
    for case in cases {
      soft
      .expect_call(() => canon(case.0), label=case.0)
      .to_return()
      .to_equal(case.1)
    }
  })
}

///|
test "operators and parentheses" {
  check_prints([
    ("a+b*c", "a + b * c"),
    ("(a+b)*c", "(a + b) * c"),
    ("a-(b-c)", "a - (b - c)"),
    ("(a-b)-c", "a - b - c"),
    ("a/(b*c)", "a / (b * c)"),
    ("- -1", "- -1"),
    ("-(-1)", "- -1"),
    ("-(a+b)", "-(a + b)"),
    ("a||b||c", "a || b || c"),
    ("a || (b || c)", "a || (b || c)"),
    ("a=b AND c<>d OR NOT e", "a = b AND c <> d OR NOT e"),
    ("a != b", "a <> b"),
    ("(a OR b) AND c", "(a OR b) AND c"),
    ("a AND (b AND c)", "a AND (b AND c)"),
    ("NOT (a = b)", "NOT a = b"),
    ("(NOT a) = b", "(NOT a) = b"),
    ("a IS TRUE IS NOT FALSE", "a IS TRUE IS NOT FALSE"),
    ("a IS NOT NULL AND b IS MISSING", "a IS NOT NULL AND b IS MISSING"),
    ("x IS INT", "x IS INT"),
    ("(x IS ARRAY) <= y", "(x IS ARRAY) <= y"),
    ("(x IS ARRAY) < y", "(x IS ARRAY) < y"),
    ("x IS ARRAY = y", "x IS ARRAY = y"),
    ("x NOT LIKE 'a%' ESCAPE '!'", "x NOT LIKE 'a%' ESCAPE '!'"),
    ("x BETWEEN a + 1 AND b", "x BETWEEN a + 1 AND b"),
    ("x BETWEEN (a AND b) AND c", "x BETWEEN (a AND b) AND c"),
    ("x IN (1, 2)", "x IN (1, 2)"),
    ("x IN (5)", "x IN (5)"),
    ("x NOT IN y", "x NOT IN y"),
    ("x IN (SELECT a FROM t)", "x IN (SELECT a FROM t)"),
    ("a < (b < c)", "a < (b < c)"),
    ("(a < b) < c", "a < b < c"),
    ("(a, b) OVERLAPS (c, d)", "(a, b) OVERLAPS (c, d)"),
  ])
}

///|
test "literals, names and quoting" {
  check_prints([
    ("1.50", "1.50"),
    ("3e2", "3e2"),
    ("'it''s'", "'it''s'"),
    ("\"Quoted\"\"Name\"", "\"Quoted\"\"Name\""),
    ("@x", "@x"),
    ("?", "?"),
    ("true AND null IS missing", "TRUE AND NULL IS MISSING"),
    ("`{a: 1, b: \"x\"}`", "`{a: 1, b: \"x\"}`"),
    ("DATE '2021-08-22'", "DATE '2021-08-22'"),
    ("TIME (3) WITH TIME ZONE '12:00:00'", "TIME(3) WITH TIME ZONE '12:00:00'"),
    ("TIMESTAMP '2021-08-22 12:00:00'", "TIMESTAMP '2021-08-22 12:00:00'"),
    ("INTERVAL '1-2' YEAR TO MONTH", "INTERVAL '1-2' YEAR TO MONTH"),
    ("INTERVAL -'5' DAY (2)", "INTERVAL -'5' DAY(2)"),
    ("INTERVAL '1.5' SECOND (2, 3)", "INTERVAL '1.5' SECOND(2, 3)"),
    ("'héllo' || \"日本\"", "'héllo' || \"日本\""),
  ])
}

///|
test "paths and collections" {
  check_prints([
    ("a.b[0].\"C\".*", "a.b[0].\"C\".*"),
    ("a[*].'k'", "a[*].'k'"),
    ("(a + b).c", "(a + b).c"),
    ("(1).a", "(1).a"),
    ("x.year", "x.year"),
    ("[1, [2]]", "[1, [2]]"),
    ("<<1, <<>>>>", "<<1, <<>>>>"),
    ("{'a': 1, 'b': {}}", "{'a': 1, 'b': {}}"),
    ("MAP{'k': 1}", "MAP{'k': 1}"),
    ("SEXP(1, 2)", "SEXP(1, 2)"),
    ("LIST(1, 2)", "[1, 2]"),
    ("BAG(1)", "<<1>>"),
    ("ROW(1)", "ROW(1)"),
    ("(1, 2)", "(1, 2)"),
    ("a > <<1>>", "a > <<1>>"),
    ("<<a > b>>", "<<a > b>>"),
  ])
}

///|
test "special forms and calls" {
  check_prints([
    ("cast(x as decimal(5,2))", "CAST(x AS DECIMAL(5, 2))"),
    ("CAST(x AS INTEGER)", "CAST(x AS INT)"),
    ("CAST(x AS DOUBLE PRECISION)", "CAST(x AS DOUBLE PRECISION)"),
    ("CAST(x AS FLOAT(10))", "CAST(x AS FLOAT(10))"),
    (
      "CAST(x AS MAP<STRING, MAP<INT, INT>>)", "CAST(x AS MAP<STRING, MAP<INT, INT>>)",
    ),
    ("CAST(x AS CHARACTER VARYING(3))", "CAST(x AS VARCHAR(3))"),
    ("CAST(x AS TIME WITH TIME ZONE)", "CAST(x AS TIME WITH TIME ZONE)"),
    ("extract(year from x)", "EXTRACT(YEAR FROM x)"),
    ("trim(x)", "TRIM(x)"),
    ("trim(from x)", "TRIM(x)"),
    ("trim(leading from x)", "TRIM(LEADING FROM x)"),
    ("trim('a' from x)", "TRIM('a' FROM x)"),
    ("trim(both 'a' from x)", "TRIM(BOTH 'a' FROM x)"),
    ("substring(x, 2, 3)", "SUBSTRING(x FROM 2 FOR 3)"),
    ("substring(x from 2)", "SUBSTRING(x FROM 2)"),
    ("position('a' in x)", "POSITION('a' IN x)"),
    (
      "overlay(x placing 'b' from 1 for 2)", "OVERLAY(x PLACING 'b' FROM 1 FOR 2)",
    ),
    ("coalesce(a, b)", "COALESCE(a, b)"),
    ("nullif(a, b)", "NULLIF(a, b)"),
    ("date_add(day, 1, x)", "DATE_ADD(DAY, 1, x)"),
    ("date_diff(year, a, b)", "DATE_DIFF(YEAR, a, b)"),
    ("count(*)", "count(*)"),
    ("count(distinct x)", "count(DISTINCT x)"),
    ("upper(x)", "upper(x)"),
    ("f()", "f()"),
    ("f((SELECT a FROM t))", "f(SELECT a FROM t)"),
    ("case when a then 1 else 2 end", "CASE WHEN a THEN 1 ELSE 2 END"),
    (
      "case x when 1 then 'a' when 2 then 'b' end", "CASE x WHEN 1 THEN 'a' WHEN 2 THEN 'b' END",
    ),
  ])
}

///|
test "error nodes print as a comment" {
  let error_expr : @ast.Expr = { kind: Error, span: { start: 0, end: 0, }, }
  let s = @parser.parse_statement("SELECT a FROM t")
  guard s is Query({ body: Select(sel), .. } as q) else { fail("not a select") }
  let broken : @ast.Statement = Query({
    ..q,
    body: Select({ ..sel, where_: Some(error_expr), }),
  })
  @expect.expect_all(soft => {
    soft
    .expect(@printer.print(broken))
    .to_equal("SELECT a FROM t WHERE /* error */")
    soft
    .expect(@printer.print(@ast.Statement::Error({ start: 0, end: 0, })))
    .to_equal("/* error */")
  })
}
