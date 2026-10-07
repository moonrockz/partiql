///|
/// A pattern element after the escape is applied.
priv enum Wild {
  Lit(Char)
  One
  Many
}

///|
fn chars_of(s : String) -> Array[Char] {
  Array::from_iter(s.iter())
}

///|
/// Applies the escape: an escape before `%`, `_` or itself makes the next
/// character literal; before anything else, or at the end, it is an error.
fn compile_pattern(
  pattern : String,
  escape : Char?,
) -> Array[Wild] raise OpFailure {
  let out : Array[Wild] = []
  let chars = chars_of(pattern)
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if Some(c) == escape {
      if i + 1 >= chars.length() {
        raise DataFailure("LIKE pattern ends with the escape character")
      }
      let next = chars[i + 1]
      if next == '%' || next == '_' || Some(next) == escape {
        out.push(Lit(next))
        i += 2
      } else {
        raise DataFailure("LIKE escape character before an ordinary character")
      }
    } else {
      out.push(
        match c {
          '%' => Many
          '_' => One
          _ => Lit(c)
        },
      )
      i += 1
    }
  }
  out
}

///|
/// Iterative wildcard matching: on a mismatch, back up to the last `%` and
/// let it take one more character.
fn wildcard_match(text : Array[Char], pat : Array[Wild]) -> Bool {
  let mut t = 0
  let mut p = 0
  let mut star = -1
  let mut mark = 0
  while t < text.length() {
    let step = if p < pat.length() {
      match pat[p] {
        Many => {
          star = p
          mark = t
          p += 1
          true
        }
        One => {
          t += 1
          p += 1
          true
        }
        Lit(c) =>
          if c == text[t] {
            t += 1
            p += 1
            true
          } else {
            false
          }
      }
    } else {
      false
    }
    if !step {
      if star < 0 {
        return false
      }
      mark += 1
      t = mark
      p = star + 1
    }
  }
  while p < pat.length() && pat[p] is Many {
    p += 1
  }
  p == pat.length()
}

///|
/// `text LIKE pattern [ESCAPE escape]`. MISSING if an operand is MISSING,
/// else NULL if one is NULL, else a type failure unless all are strings.
pub fn like(
  text : @value.Value,
  pattern : @value.Value,
  escape : @value.Value?,
) -> @value.Value raise OpFailure {
  let operands = [boxed(text), boxed(pattern)]
  match escape {
    Some(e) => operands.push(boxed(e))
    None => ()
  }
  if operands.any(v => v is Missing) {
    return Missing
  }
  if operands.any(v => v is Null) {
    return Null
  }
  match operands {
    [String(t), String(p)] =>
      Bool(wildcard_match(chars_of(t), compile_pattern(p, None)))
    [String(t), String(p), String(e)] => {
      let units = chars_of(e)
      guard units.length() == 1 else {
        raise DataFailure("LIKE escape must be one character")
      }
      Bool(wildcard_match(chars_of(t), compile_pattern(p, Some(units[0]))))
    }
    _ => raise TypeFailure("LIKE of a value that is not a string")
  }
}
