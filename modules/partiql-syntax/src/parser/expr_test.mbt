///|
fn check_shapes(cases : Array[(String, String)]) -> Unit raise {
  @expect.expect_all(soft => {
    for case in cases {
      soft.expect(expr_shape(case.0), label=case.0).to_equal(case.1)
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
    ("'it''s'", "'it's'"),
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
    ("SEXP()", "(sexp )"),
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
      expected.contains("']'")
    },
    description="Syntax at the end, expecting ']'",
  )
}
