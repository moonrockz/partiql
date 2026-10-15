// The text functions (spec M4d1 §5). Positions and lengths count Unicode
// code points, never UTF-16 code units.

///|
/// The number of UTF-8 bytes of `s`.
fn utf8_length(s : String) -> Int64 {
  let mut n = 0L
  for c in s {
    let cp = c.to_int()
    n += if cp < 0x80 {
      1L
    } else if cp < 0x800 {
      2L
    } else if cp < 0x10000 {
      3L
    } else {
      4L
    }
  }
  n
}

///|
/// `CHAR_LENGTH(s)`: the number of code points.
pub fn char_length(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  apply("CHAR_LENGTH", [Text], args, xs => {
    match xs {
      [String(s)] => Int(chars_of(s).length().to_int64())
      _ => raise TypeFailure("CHAR_LENGTH of a value that is not a string")
    }
  })
}

///|
/// The number of bytes: UTF-8 for a string.
fn byte_count(
  name : String,
  args : Array[@value.Value],
) -> @value.Value raise OpFailure {
  apply(name, [Bytes], args, xs => {
    match xs {
      [String(s)] => Int(utf8_length(s))
      [Blob(b)] | [Clob(b)] => Int(b.length().to_int64())
      _ => raise TypeFailure("\{name} of a value that is not a string")
    }
  })
}

///|
/// `OCTET_LENGTH(s)`: UTF-8 bytes of a string; bytes of a blob or clob.
pub fn octet_length(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  byte_count("OCTET_LENGTH", args)
}

///|
/// `BIT_LENGTH(s)`: 8 times OCTET_LENGTH.
pub fn bit_length(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  match byte_count("BIT_LENGTH", args) {
    Int(n) => Int(n * 8L)
    other => other
  }
}
