///|
fn syntax(
  message : String,
  start : Int,
  end : Int,
  expected : Array[String],
  found : String,
) -> @ast.ParseError {
  Syntax(message~, span={ start, end, }, expected~, found~)
}

///|
test "positions count code points, lines from 1" {
  @expect.expect_all(soft => {
    soft
    .expect(@diagnostic.position("SELECT FROM t", 7))
    .to_equal({ line: 1, column: 8, })
    soft
    .expect(@diagnostic.position("a\r\nb", 3))
    .to_equal({ line: 2, column: 1, })
    soft
    .expect(@diagnostic.position("'😀' + FROM", 7))
    .to_equal({ line: 1, column: 7, })
    soft
    .expect(@diagnostic.position("'日本' + FROM", 7))
    .to_equal({ line: 1, column: 8, })
  })
}

///|
test "render: a basic error" {
  let e = syntax(
    "expected an expression",
    7,
    11,
    ["DISTINCT", "ALL", "`*`", "VALUE", "an expression"],
    "keyword `FROM`",
  )
  @expect.expect(@diagnostic.render(e, "SELECT FROM t", name="query.sql")).to_equal(
    (
      #|error: expected an expression, found keyword `FROM`
      #| --> query.sql:1:8
      #|  |
      #|1 | SELECT FROM t
      #|  |        ^^^^ expected an expression
      #|  |
      #|  = expected: DISTINCT, ALL, `*`, VALUE or an expression
      #|
    ),
  )
}

///|
test "render: errors at the end of input" {
  let e = syntax(
    "expected an expression",
    13,
    13,
    ["LATERAL", "UNPIVOT", "an expression"],
    "end of input",
  )
  let expected =
    #|error: expected an expression, found end of input
    #| --> q:1:14
    #|  |
    #|1 | SELECT a FROM
    #|  |              ^ expected an expression
    #|  |
    #|  = expected: LATERAL, UNPIVOT or an expression
    #|
  @expect.expect_all(soft => {
    soft
    .expect(@diagnostic.render(e, "SELECT a FROM", name="q"))
    .to_equal(expected)
    soft
    .expect(
      @diagnostic.render(
        syntax(
          "expected an expression",
          14,
          14,
          ["LATERAL", "UNPIVOT", "an expression"],
          "end of input",
        ),
        "SELECT a FROM\n",
        name="q",
      ),
    )
    .to_equal(expected)
    soft
    .expect(
      @diagnostic.render(
        syntax(
          "expected an expression",
          15,
          15,
          ["LATERAL", "UNPIVOT", "an expression"],
          "end of input",
        ),
        "SELECT a FROM\r\n",
        name="q",
      ),
    )
    .to_equal(expected)
  })
}

///|
test "render: tabs, CRLF, wide characters, long line numbers" {
  @expect.expect_all(soft => {
    soft
    .expect(
      @diagnostic.render(
        syntax("expected an expression", 8, 12, [], "keyword `FROM`"),
        "\tSELECT\tFROM t",
        name="t",
      ),
    )
    .to_equal(
      (
        #|error: expected an expression, found keyword `FROM`
        #| --> t:1:9
        #|  |
        #|1 |     SELECT    FROM t
        #|  |               ^^^^ expected an expression
        #|
      ),
    )
    soft
    .expect(
      @diagnostic.render(
        syntax("expected an expression", 18, 22, [], "keyword `FROM`"),
        "SELECT 1;\r\nSELECT FROM t\r\n",
        name="c",
      ),
    )
    .to_equal(
      (
        #|error: expected an expression, found keyword `FROM`
        #| --> c:2:8
        #|  |
        #|2 | SELECT FROM t
        #|  |        ^^^^ expected an expression
        #|
      ),
    )
    soft
    .expect(
      @diagnostic.render(
        syntax("expected an expression", 7, 11, [], "keyword `FROM`"),
        "'😀' + FROM",
        name="w",
      ),
    )
    .to_equal(
      (
        #|error: expected an expression, found keyword `FROM`
        #| --> w:1:7
        #|  |
        #|1 | '😀' + FROM
        #|  |       ^^^^ expected an expression
        #|
      ),
    )
    let source = "\n".repeat(100) + "SELECT FROM"
    soft
    .expect(
      @diagnostic.render(
        syntax("expected an expression", 107, 111, [], "keyword `FROM`"),
        source,
        name="n",
      ),
    )
    .to_equal(
      (
        #|error: expected an expression, found keyword `FROM`
        #|   --> n:101:8
        #|    |
        #|101 | SELECT FROM
        #|    |        ^^^^ expected an expression
        #|
      ),
    )
  })
}

///|
test "render: Unsupported, lexer errors, spans over lines" {
  @expect.expect_all(soft => {
    soft
    .expect(
      @diagnostic.render(
        Unsupported(message="INSERT statements are not supported yet", span={
          start: 0,
          end: 6,
        }),
        "INSERT INTO t VALUE 1",
        name="d",
      ),
    )
    .to_equal(
      (
        #|error: INSERT statements are not supported yet
        #| --> d:1:1
        #|  |
        #|1 | INSERT INTO t VALUE 1
        #|  | ^^^^^^
        #|
      ),
    )
    soft
    .expect(
      @diagnostic.render(
        syntax("unterminated string", 7, 8, [], ""),
        "SELECT 'abc",
        name="s",
      ),
    )
    .to_equal(
      (
        #|error: unterminated string
        #| --> s:1:8
        #|  |
        #|1 | SELECT 'abc
        #|  |        ^
        #|
      ),
    )
    soft
    .expect(
      @diagnostic.render(
        syntax("unterminated comment", 0, 9, [], ""),
        "/* a\nb */ x\n",
        name="m",
      ),
    )
    .to_equal(
      (
        #|error: unterminated comment
        #| --> m:1:1
        #|  |
        #|1 | /* a
        #|  | ^^^^
        #|  |
        #|  = note: the span ends at line 2
        #|
      ),
    )
  })
}

///|
test "render: colour" {
  let text = @diagnostic.render(
    syntax("expected an expression", 7, 11, ["a", "b"], "keyword `FROM`"),
    "SELECT FROM t",
    name="q",
    color=true,
  )
  @expect.expect_all(soft => {
    soft.expect(text.contains("\u{1b}[1;31merror\u{1b}[0m")).to_be_true()
    soft.expect(text.contains("\u{1b}[1;34m-->\u{1b}[0m")).to_be_true()
    soft
    .expect(text.contains("\u{1b}[1;31m^^^^ expected an expression\u{1b}[0m"))
    .to_be_true()
    soft
    .expect(
      @diagnostic.render(syntax("x", 0, 1, [], ""), "y", name="q").contains(
        "\u{1b}",
      ),
    )
    .to_be_false()
  })
}

///|
test "render: control characters in the source line do not reach the terminal" {
  let text = @diagnostic.render(
    syntax("unexpected character U+001B", 1, 2, [], ""),
    "a\u{1b}[31mb",
    name="c",
  )
  @expect.expect(text.contains("\u{1b}")).to_be_false()
}
