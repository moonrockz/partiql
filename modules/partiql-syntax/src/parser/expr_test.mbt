///|
fn check_shapes(cases : Array[(String, String)]) -> Unit raise {
  @expect.expect_all(soft => {
    for case in cases {
      soft
      .expect_call(() => expr_shape(case.0), label=case.0)
      .to_return()
      .to_equal(case.1)
    }
  })
}

///|
fn check_failures(sources : Array[String]) -> Unit raise {
  @expect.expect_all(soft => {
    for source in sources {
      soft
      .expect_call(() => @parser.parse_expression(source), label=source)
      .to_raise_matching(syntax_error, description="Syntax")
    }
  })
}

///|
test "operator precedence" {
  check_shapes([
    ("1 + 2 * 3", "(+ 1 (* 2 3))"),
    ("(1 + 2) * 3", "(* (+ 1 2) 3)"),
    ("a OR b AND NOT c", "(or a (and b (not c)))"),
    ("a = b = c", "(= (= a b) c)"),
    ("a <> b", "(<> a b)"),
    ("a != b", "(<> a b)"),
    ("a <= b", "(<= a b)"),
    ("a>=b", "(>= a b)"),
    ("-a.b", "(neg (path a .b))"),
    ("a || b + c", "(|| a (+ b c))"),
    ("a < -1", "(< a (neg 1))"),
    ("a<-1", "(< a (neg 1))"),
    ("+-+-1", "(pos (neg (pos (neg 1))))"),
    ("10 % 3 / 2", "(/ (% 10 3) 2)"),
    ("NOT a = b", "(not (= a b))"),
  ])
}

///|
test "predicates" {
  check_shapes([
    ("a LIKE 'x%'", "(like a 'x%')"),
    ("a NOT LIKE 'x!%' ESCAPE '!'", "(not-like a 'x!%' '!')"),
    ("a BETWEEN 1 AND 2", "(between a 1 2)"),
    ("a NOT BETWEEN 1 AND 2 AND b", "(and (not-between a 1 2) b)"),
    ("a IN [1, 2]", "(in a [1 2])"),
    ("a NOT IN (1, 2)", "(not-in a (row 1 2))"),
    ("(a, b) IN ((1, 2), (3, 4))", "(in (row a b) (row (row 1 2) (row 3 4)))"),
    ("a IS NULL", "(is-null a)"),
    ("a IS NOT MISSING", "(not-is-missing a)"),
    ("a IS TRUE", "(is-true a)"),
    ("a IS NOT UNKNOWN", "(not-is-unknown a)"),
    ("a IS INT", "(is a INT)"),
    ("a IS NOT VARCHAR(200)", "(not-is a VARCHAR(200))"),
    ("a IS MAP<STRING, INTEGER>", "(is a MAP<STRING,INT>)"),
    ("a = b IS NULL", "(is-null (= a b))"),
  ])
}

///|
test "literals" {
  check_shapes([
    ("1", "1"),
    ("1.50", "1.50"),
    ("-5e0", "(neg 5e0)"),
    ("'it''s'", "'it''s'"),
    ("NULL", "null"),
    ("missing", "missing"),
    ("TRUE", "true"),
    ("`{a: 1}`", "`{a: 1}`"),
    ("123456789012345678901234567890", "123456789012345678901234567890"),
  ])
}

///|
test "variables, parameters and paths" {
  check_shapes([
    ("x", "x"),
    ("\"X\"", "\"X\""),
    ("@x", "@x"),
    ("?", "?"),
    ("a.b[1].c", "(path a .b [1] .c)"),
    ("a[*].*[*].b.*[3+4]", "(path a [*] .* [*] .b .* [(+ 3 4)])"),
    ("{'a': 1}.'a'", "(path {'a':1} .'a')"),
    ("x.year", "(path x .year)"),
    ("r.timestamp", "(path r .timestamp)"),
    ("a.\"B\"", "(path a .\"B\")"),
    ("count.x", "(path count .x)"),
  ])
}

///|
test "collections" {
  check_shapes([
    ("[1, 2]", "[1 2]"),
    ("[]", "[]"),
    ("<<1, <<>>>>", "<<1 <<>>>>"),
    ("<<<<>>>>", "<<<<>>>>"),
    ("{a: 1, 'b': c}", "{a:1 'b':c}"),
    ("{}", "{}"),
    ("MAP{'k': 1}", "(map 'k':1)"),
    ("LIST(1, 2)", "[1 2]"),
    ("SEXP()", "(sexp)"),
    ("ROW(1, 2)", "(row 1 2)"),
    ("(1, 2)", "(row 1 2)"),
  ])
}

///|
test "calls" {
  check_shapes([
    ("f()", "(call f)"),
    ("upper(x)", "(call upper x)"),
    ("count(*)", "(call count *)"),
    ("COUNT(DISTINCT x)", "(call COUNT distinct x)"),
    ("sum(ALL x)", "(call sum all x)"),
    ("exists(x)", "(call exists x)"),
    ("size(x, 1)", "(call size x 1)"),
  ])
}

///|
test "expression syntax errors" {
  check_failures([
    "5 5", "x...a", "foo.table", "@", "@ @a", "@(a)", "(1 + 2", "[1, 2", "{a 1}",
    "1 +", "a BETWEEN 1", "a LIKE", "a IS", "SELECT", "true.x.", "a.b.[*]", "a.b.['item']",
    "a.b.{'a': 1}.a", "a.b.[1,2,3][2]", "<<1>", "(1;)", "a NOT", "5 BETWEEN 1 10",
  ])
}

///|
test "errors report what was expected" {
  @expect.expect_call(() => @parser.parse_expression("[1, 2")).to_raise_matching(
    e => {
      e
      is @ast.ParseError::Syntax(
        span={ start: 5, end: 5, },
        found="end of input",
        expected~,
        ..
      ) &&
      expected.contains("`]`")
    },
    description="Syntax at the end, expecting ']'",
  )
}

///|
test "IN keeps a parenthesized right operand as a row" {
  // The corpus gives `x IN (5)` and `x IN 5` different results.
  check_shapes([
    ("a IN (5)", "(in a (row 5))"),
    ("a IN 5", "(in a 5)"),
    ("a IN (prices)", "(in a (row prices))"),
    ("a NOT IN (1, 2)", "(not-in a (row 1 2))"),
    ("a IN (SELECT VALUE x FROM t)", "(in a (select (value x) (from t)))"),
  ])
}

///|
test "parentheses around an expression with a subquery do not make a subquery" {
  // (The shape renderer flattens a query whose body is an expression, so this
  // test looks at the node kinds.)
  @expect.expect_all(soft => {
    soft
    .expect(
      @parser.parse_expression("((SELECT 1) + 1)").kind is Binary(Add, _, _),
    )
    .to_be_true()
    soft
    .expect(
      @parser.parse_expression("f((SELECT 1) + 1)").kind
      is Call(_, [{ kind: Binary(Add, _, _), .. }], ..),
    )
    .to_be_true()
    soft
    .expect(@parser.parse_expression("((SELECT 1))").kind is Query(_))
    .to_be_true()
  })
}

///|
test "a row or call whose first item is a parenthesized query" {
  check_shapes([
    ("((SELECT 1), 2)", "(row (select 1) 2)"),
    ("f((SELECT a), b)", "(call f (select a) b)"),
    ("x IN ((VALUES (1)), 2)", "(in x (row (values (row 1)) 2))"),
    ("(((SELECT 1)), 2)", "(row (select 1) 2)"),
    (
      "((SELECT 1) UNION (SELECT 2), 3)", "(row (union (select 1) (select 2)) 3)",
    ),
    ("f((SELECT a))", "(call f (select a))"),
    ("((SELECT 1))", "(select 1)"),
  ])
  check_failures(["((SELECT 1), )", "f((SELECT a), )", "((SELECT 1) 2)"])
}

///|
test "a row has no trailing comma" {
  check_failures(["(1, )", "x IN (1, )", "(a, b, )"])
}
