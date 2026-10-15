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

///|
fn text_of(cs : ArrayView[Char]) -> String {
  let b = StringBuilder()
  for c in cs {
    b.write_char(c)
  }
  b.to_string()
}

///|
fn big_of(v : @value.Value) -> @bigint.BigInt raise OpFailure {
  match v {
    Int(n) => @bigint.BigInt::from_int64(n)
    BigInt(n) => n
    _ => raise TypeFailure("a position that is not an integer")
  }
}

///|
/// SQL-92 6.7 GR 3 over code points: from position `start`, `length` code
/// points, or to the end without a length. E = start + length; a negative
/// length is a substring error, a `TypeFailure` (partiql-tests
/// substring.ion:1310). BigInt arithmetic: no overflow.
fn slice(
  cs : Array[Char],
  start : @bigint.BigInt,
  length : @bigint.BigInt?,
) -> String raise OpFailure {
  let one = @bigint.BigInt::from_int(1)
  let size = @bigint.BigInt::from_int(cs.length())
  let end = match length {
    Some(l) => {
      if is_negative_int(l) {
        raise TypeFailure("SUBSTRING with a negative length")
      }
      start + l
    }
    None => if size + one > start { size + one } else { start }
  }
  if start > size || end < one {
    return ""
  }
  let from = if start < one { one } else { start }
  let to = if end < size + one { end } else { size + one }
  text_of(cs[from.to_int() - 1:to.to_int() - 1])
}

///|
/// `SUBSTRING(v FROM start [FOR length])`.
pub fn substring(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  let params : Array[Param] = if args.length() == 2 {
    [Text, Integer]
  } else {
    [Text, Integer, Integer]
  }
  apply("SUBSTRING", params, args, xs => {
    match xs {
      [String(v), start] => String(slice(chars_of(v), big_of(start), None))
      [String(v), start, length] =>
        String(slice(chars_of(v), big_of(start), Some(big_of(length))))
      _ => raise TypeFailure("SUBSTRING of a value that is not a string")
    }
  })
}

///|
/// The first index at or after `from` where `needle` occurs in `hay`.
fn index_of(hay : Array[Char], needle : Array[Char], from~ : Int32) -> Int32? {
  let last = hay.length() - needle.length()
  let mut i = from
  while i <= last {
    let mut k = 0
    while k < needle.length() && hay[i + k] == needle[k] {
      k += 1
    }
    if k == needle.length() {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// `POSITION(needle IN hay)`: the 1-based code-point index, 0 when absent,
/// 1 for an empty needle (SQL).
pub fn position(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  apply("POSITION", [Text, Text], args, xs => {
    match xs {
      [String(needle), String(hay)] =>
        match index_of(chars_of(hay), chars_of(needle), from=0) {
          Some(i) => Int((i + 1).to_int64())
          None => Int(0L)
        }
      _ => raise TypeFailure("POSITION of a value that is not a string")
    }
  })
}

///|
/// `OVERLAY(v PLACING r FROM s [FOR n])` = `SUBSTRING(v FROM 1 FOR s - 1) ||
/// r || SUBSTRING(v FROM s + n)`, n = CHAR_LENGTH(r) by default
/// (SQL:1999 6.18). s < 1 is a substring error (negative length).
pub fn overlay(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  let params : Array[Param] = if args.length() == 3 {
    [Text, Text, Integer]
  } else {
    [Text, Text, Integer, Integer]
  }
  apply("OVERLAY", params, args, xs => {
    let (v, r, start, length) = match xs {
      [String(v), String(r), s] =>
        (v, r, big_of(s), @bigint.BigInt::from_int(chars_of(r).length()))
      [String(v), String(r), s, n] => (v, r, big_of(s), big_of(n))
      _ => raise TypeFailure("OVERLAY of a value that is not a string")
    }
    let cs = chars_of(v)
    let one = @bigint.BigInt::from_int(1)
    String(
      slice(cs, one, Some(start - one)) + r + slice(cs, start + length, None),
    )
  })
}

///|
/// `TEXT_REPLACE(v, pattern, replacement)`: every non-overlapping match from
/// the left; an empty pattern inserts at every code-point boundary
/// (partiql-tests extended text_replace.ion:39).
pub fn text_replace(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  apply("TEXT_REPLACE", [Text, Text, Text], args, xs => {
    match xs {
      [String(v), String(p), String(r)] => {
        let cs = chars_of(v)
        let pattern = chars_of(p)
        let b = StringBuilder()
        if pattern.is_empty() {
          b.write_string(r)
          for c in cs {
            b.write_char(c)
            b.write_string(r)
          }
          return String(b.to_string())
        }
        let mut i = 0
        while i < cs.length() {
          match index_of(cs, pattern, from=i) {
            Some(at) => {
              b.write_string(text_of(cs[i:at]))
              b.write_string(r)
              i = at + pattern.length()
            }
            None => {
              b.write_string(text_of(cs[i:]))
              i = cs.length()
            }
          }
        }
        String(b.to_string())
      }
      _ => raise TypeFailure("TEXT_REPLACE of a value that is not a string")
    }
  })
}

///|
/// `TRIM([spec] [chars] FROM v)`: removes code points of the set `chars`
/// (default U+0020) from the chosen ends. Arguments: [v] or [v, chars].
pub fn trim(
  spec : @ast.TrimSpec,
  args : Array[@value.Value],
) -> @value.Value raise OpFailure {
  apply("TRIM", Array::make(args.length(), Param::Text), args, xs => {
    let (v, set) = match xs {
      [String(v)] => (v, [' '])
      [String(v), String(c)] => (v, chars_of(c))
      _ => raise TypeFailure("TRIM of a value that is not a string")
    }
    let cs = chars_of(v)
    let mut from = 0
    let mut to = cs.length()
    if spec is (Both | Leading) {
      while from < to && set.contains(cs[from]) {
        from += 1
      }
    }
    if spec is (Both | Trailing) {
      while to > from && set.contains(cs[to - 1]) {
        to -= 1
      }
    }
    String(text_of(cs[from:to]))
  })
}
