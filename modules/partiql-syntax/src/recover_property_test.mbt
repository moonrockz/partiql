// Laws of error recovery (spec M3d §5).

///|
/// Valid statements with one word deleted or one junk piece inserted, and
/// token soup with valid and broken Ion literals.
struct BrokenText {
  text : String
} derive(Debug)

///|
let broken_pieces : Array[String] = [
  "SELECT", "FROM", "WHERE", "GROUP", "BY", "ORDER", "a", "t", "1", ",", "(", ")",
  "[", "]", "{", "}", "<<", ">>", ":", ";", "=", "+", "AND", "'s'", "`{a: 1}`", "`{a:`",
  "`[1, 2]`", "`abc", "#", "MATCH", "VALUES", "CASE", "END", "JOIN", "ON", "'open",
  "/*",
]

///|
let broken_bases : Array[String] = [
  "SELECT a , b FROM t WHERE x = 1 ORDER BY a", "SELECT f ( a , b ) FROM t AS x",
  "VALUES ( 1 , 2 ) , ( 3 , 4 )", "SELECT { 'k' : `{a: 1}` } FROM t ; SELECT 2",
  "( g MATCH ( a ) -[ e ]-> ( b ) )", "SELECT * FROM ( a JOIN b ON x ) , c", "SELECT a FROM t GROUP BY a HAVING a > 1 LIMIT 2 OFFSET 1",
  "SELECT << 1 , [ 2 , 3 ] >> FROM t",
]

///|
impl @quickcheck.Arbitrary for BrokenText with fn arbitrary(size, rs) {
  let pick = (n : Int) => {
    rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
  }
  let base = () => {
    broken_bases[pick(broken_bases.length())]
    .split(" ")
    .map(v => v.to_owned())
    .collect()
  }
  match pick(3) {
    0 => {
      let words = base()
      ignore(words.remove(pick(words.length())))
      { text: words.join(" "), }
    }
    1 => {
      let words = base()
      words.insert(
        pick(words.length() + 1),
        broken_pieces[pick(broken_pieces.length())],
      )
      { text: words.join(" "), }
    }
    _ => {
      let n = 1 + pick(size + 1)
      let words = Array::makei(n, _ => {
        broken_pieces[pick(broken_pieces.length())]
      })
      { text: words.join(" "), }
    }
  }
}

///|
impl @quickcheck.Shrink for BrokenText

///|
fn start_of(e : @syntax.ParseError) -> Int {
  match e {
    Syntax(span~, ..) | Unsupported(span~, ..) => span.start
  }
}

///|
fn span_ok(e : @syntax.ParseError, length : Int) -> Bool {
  match e {
    Syntax(span~, ..) | Unsupported(span~, ..) =>
      span.start >= 0 && span.start <= span.end && span.end <= length
  }
}

///|
/// The laws of spec M3d §5 for one source.
fn recovery_holds(text : String) -> Bool {
  let r = @syntax.parse_script_recovering(text)
  let mut ordered = true
  for i in 1..<r.errors.length() {
    if start_of(r.errors[i - 1]) > start_of(r.errors[i]) {
      ordered = false
    }
  }
  let strict_listed = try @syntax.parse_script(text) catch {
    e => r.errors.contains(e)
  } noraise {
    s => r.errors.is_empty() && r.script == s
  }
  ordered &&
  r.errors.length() <= 100 &&
  r.errors.iter().all(e => span_ok(e, text.length())) &&
  strict_listed
}

///|
test "law: recovery on broken input" {
  @quickcheck.check((b : BrokenText) => recovery_holds(b.text), count=2000)
}

///|
test "law: recovery on token soup" {
  @quickcheck.check((s : SoupText) => recovery_holds(s.text), count=1000)
}

///|
test "law: recovery on valid input with comments" {
  @quickcheck.check((c : CommentedText) => recovery_holds(c.text), count=500)
}
