///|
/// PartiQL-flavoured source text: words, numbers, quotes, backticks,
/// operators and whitespace, so random input reaches deep into the lexer and
/// the parser.
struct SoupText {
  text : String
} derive(Debug)

///|
let soup_pieces : Array[String] = [
  "SELECT", "VALUE", "FROM", "WHERE", "GROUP", "BY", "AS", "AT", "JOIN", "ON", "UNION",
  "ALL", "ORDER", "LIMIT", "CASE", "WHEN", "THEN", "END", "CAST", "TRIM", "NOT",
  "IS", "NULL", "MISSING", "IN", "LIKE", "BETWEEN", "AND", "OR", "TIME", "DATE",
  "INTERVAL", "MAP", "x", "\"q\"", "1", "2.5", "3e2", "'s'", "`1`", "`{a:1}`", "(",
  ")", "[", "]", "{", "}", "<", ">", "<<", ">>", ",", ".", ":", ";", "*", "+", "-",
  "/", "%", "=", "!", "|", "@", "?", "'", "`", "\"", "--", "/*", "*/", " ", "\n",
]

///|
impl @quickcheck.Arbitrary for SoupText with fn arbitrary(size, rs) {
  let n = rs
    .next_uint(limit=(size * 4 + 1).reinterpret_as_uint())
    .reinterpret_as_int()
  let buf = StringBuilder()
  for _ in 0..<n {
    let piece = soup_pieces[rs
      .next_uint(limit=soup_pieces.length().reinterpret_as_uint())
      .reinterpret_as_int()]
    buf.write_string(piece)
    if rs.next_uint(limit=2) == 0 {
      buf.write_char(' ')
    }
  }
  { text: buf.to_string(), }
}

///|
impl @quickcheck.Shrink for SoupText

///|
/// Parsing either succeeds or raises ParseError; it never aborts.
fn parses_or_raises(source : String) -> Bool {
  try @syntax.parse(source) catch {
    _ => true
  } noraise {
    _ => true
  }
}

///|
test "parse never aborts on arbitrary strings" {
  @quickcheck.check((s : String) => parses_or_raises(s), count=500)
}

///|
test "parse never aborts on PartiQL soup" {
  @quickcheck.check((s : SoupText) => parses_or_raises(s.text), count=1000)
}

///|
fn too_deep(e : Error) -> Bool {
  e is @syntax.ParseError::Syntax(message="nesting is too deep", ..)
}

///|
test "deep nesting raises a syntax error, not a stack overflow" {
  let deep = (open : String, middle : String, close : String) => {
    open.repeat(1000) + middle + close.repeat(1000)
  }
  @expect.expect_all(soft => {
    for
      source in [
        deep("(", "1", ")"),
        deep("[", "1", "]"),
        deep("<<", "1", ">>"),
        deep("{'a': ", "1", "}"),
        deep("NOT ", "x", ""),
        deep("- ", "1", ""),
        deep("(SELECT VALUE ", "1", ")"),
        deep("CASE WHEN ", "x THEN 1", " THEN 1 END"),
        "CAST(x AS " +
        "MAP<INT, ".repeat(20000) +
        "INT" +
        ">".repeat(20000) +
        ")",
        "x IS " + "ARRAY<".repeat(20000) + "INT" + ">".repeat(20000),
      ] {
      soft
      .expect_call(
        () => @syntax.parse(source),
        label=source.view(end_offset=30).to_owned(),
      )
      .to_raise_matching(too_deep, description="nesting is too deep")
    }
  })
}

///|
test "nesting just below the limit parses on every target" {
  @expect.expect_all(soft => {
    soft
    .expect_call(() => @syntax.parse("(".repeat(95) + "1" + ")".repeat(95)))
    .not()
    .to_raise()
    soft
    .expect_call(() => {
      @syntax.parse("(SELECT VALUE ".repeat(45) + "1" + ")".repeat(45))
    })
    .not()
    .to_raise()
  })
}
