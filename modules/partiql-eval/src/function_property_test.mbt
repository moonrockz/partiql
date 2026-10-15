///|
/// A string of code points that stress case mapping and positions, with a
/// start and a non-negative length.
struct TextSample {
  text : String
  start : Int32
  length : Int32
} derive(Debug)

///|
let sample_pieces : Array[String] = [
  "a", "B", " ", "ß", "Σ", "σ", "😀", "e\u{0301}", "İ", "ﬁ", "話", ".",
  "ǰ",
]

///|
impl @quickcheck.Arbitrary for TextSample with fn arbitrary(_size, rs) {
  let b = StringBuilder()
  for _ in 0..<pick(rs, 8) {
    b.write_string(sample_pieces[pick(rs, sample_pieces.length())])
  }
  { text: b.to_string(), start: pick(rs, 12) - 3, length: pick(rs, 10), }
}

///|
impl @quickcheck.Shrink for TextSample

///|
/// Whether the query gives TRUE.
fn holds(source : String) -> Bool {
  try ev(source) catch {
    _ => false
  } noraise {
    v => v is Bool(true)
  }
}

///|
test "law: text function identities" {
  @quickcheck.check((x : TextSample) => {
    let t = "'\{x.text}'"
    holds("CHAR_LENGTH(UPPER(\{t})) >= CHAR_LENGTH(\{t})") &&
    holds("CHAR_LENGTH(LOWER(\{t})) >= CHAR_LENGTH(\{t})") &&
    holds("SUBSTRING(\{t} FROM 1) = \{t}") &&
    holds("OVERLAY(\{t} PLACING '' FROM 1 FOR 0) = \{t}") &&
    holds("TRIM(TRIM(\{t})) = TRIM(\{t})") &&
    holds("POSITION(\{t} IN \{t}) = 1") &&
    holds("TEXT_REPLACE(\{t}, 'a', 'a') = \{t}") &&
    holds(
      "CHAR_LENGTH(SUBSTRING(\{t} FROM \{x.start} FOR \{x.length})) <= \{x.length}",
    ) &&
    holds(
      "SUBSTRING(\{t} FROM 1 FOR \{x.length}) || SUBSTRING(\{t} FROM \{x.length + 1}) = \{t}",
    )
  })
}
