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
  "MATCH", "ANY", "SHORTEST", "TRAIL", "~", "&", "->", "<-", "-[",
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
        "(g MATCH " + "(".repeat(20000) + "(a)" + ")".repeat(20000) + ")",
        "(g MATCH " + "[".repeat(20000) + "(a)" + "]".repeat(20000) + ")",
        "(g MATCH (x:" + "(".repeat(20000) + "A" + ")".repeat(20000) + "))",
        "(g MATCH (x:" + "!(".repeat(20000) + "A" + ")".repeat(20000) + "))",
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
    soft
    .expect_call(() => {
      @syntax.parse("(g MATCH " + "(".repeat(80) + "(a)" + ")".repeat(80) + ")")
    })
    .not()
    .to_raise()
    soft
    .expect_call(() => {
      @syntax.parse(
        "(g MATCH (x:" + "(".repeat(80) + "A" + ")".repeat(80) + "))",
      )
    })
    .not()
    .to_raise()
  })
}

///|
/// Random GPML tokens inside `(g MATCH …)`.
struct GraphSoup {
  text : String
} derive(Debug)

///|
let graph_pieces : Array[String] = [
  "MATCH", "ANY", "ALL", "SHORTEST", "GROUP", "TRAIL", "WALK", "ACYCLIC", "SIMPLE",
  "WHERE", "p", "x", "1", "=", "(", ")", "[", "]", "{", "}", "-", "<", ">", "~",
  "->", "<-", "~>", ":", "|", "&", "!", "%", "+", "*", ",", "'s'", "--", " ", "\n",
]

///|
impl @quickcheck.Arbitrary for GraphSoup with fn arbitrary(size, rs) {
  let n = rs
    .next_uint(limit=(size * 4 + 1).reinterpret_as_uint())
    .reinterpret_as_int()
  let buf = StringBuilder()
  buf.write_string(
    if rs.next_uint(limit=2) == 0 {
      "(g MATCH "
    } else {
      "SELECT * FROM g MATCH "
    },
  )
  for _ in 0..<n {
    buf.write_string(
      graph_pieces[rs
      .next_uint(limit=graph_pieces.length().reinterpret_as_uint())
      .reinterpret_as_int()],
    )
    if rs.next_uint(limit=2) == 0 {
      buf.write_char(' ')
    }
  }
  if rs.next_uint(limit=2) == 0 {
    buf.write_char(')')
  }
  { text: buf.to_string(), }
}

///|
impl @quickcheck.Shrink for GraphSoup

///|
test "parse never aborts on graph soup" {
  @quickcheck.check((s : GraphSoup) => parses_or_raises(s.text), count=1000)
}

///|
test "deep input inside a parenthesized join reports the depth" {
  let deep = "(".repeat(150) + "x" + ")".repeat(150)
  @expect.expect_all(soft => {
    for
      source in [
        "SELECT * FROM (a JOIN " + deep + " ON x)",
        "SELECT * FROM (a JOIN b ON " + deep + ")",
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
/// SoupText with random comments between the pieces.
struct CommentedText {
  text : String
  comments : Array[String]
} derive(Debug)

///|
let commented_bases : Array[String] = [
  "SELECT a , b FROM t WHERE x = 1 ORDER BY a", "( g MATCH ( a ) -[ e ]-> ( b ) )",
  "SELECT VALUE { 'k' : 1 } FROM t AS x ; SELECT 2", "a UNION SELECT b FROM u LIMIT 3",
]

///|
impl @quickcheck.Arbitrary for CommentedText with fn arbitrary(_, rs) {
  let base = commented_bases[rs
    .next_uint(limit=commented_bases.length().reinterpret_as_uint())
    .reinterpret_as_int()]
  let buf = StringBuilder()
  let comments : Array[String] = []
  for i, word in base.split(" ").map(v => v.to_owned()).collect() {
    if i > 0 {
      buf.write_char(' ')
    }
    match rs.next_uint(limit=6) {
      0 => {
        let c = "/* c\{i} */"
        comments.push(c)
        buf.write_string(c + " ")
      }
      1 => {
        let c = "-- l\{i}"
        comments.push(c)
        buf.write_string(c + "\n")
      }
      _ => ()
    }
    buf.write_string(word)
  }
  { text: buf.to_string(), comments, }
}

///|
impl @quickcheck.Shrink for CommentedText

///|
test "law 3: format keeps every comment, in order, and the tree" {
  @quickcheck.check(
    (c : CommentedText) => {
      try {
        let out = @syntax.format(c.text)
        let script = @syntax.parse_script(out)
        script.comments.map(x => x.text) == c.comments &&
        script.strip_spans().statements ==
        @syntax.parse_script(c.text).strip_spans().statements
      } catch {
        _ => false
      }
    },
    count=500,
  )
}

///|
test "law 4: format is idempotent" {
  @quickcheck.check(
    (c : CommentedText) => {
      try {
        let once = @syntax.format(c.text)
        @syntax.format(once) == once
      } catch {
        _ => false
      }
    },
    count=300,
  )
}

///|
test "law 5: format never aborts" {
  @quickcheck.check(
    (s : SoupText) => {
      try {
        ignore(@syntax.format(s.text))
        true
      } catch {
        _ => true
      }
    },
    count=1000,
  )
}
