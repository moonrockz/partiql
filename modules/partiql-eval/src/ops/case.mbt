// UPPER and LOWER: Unicode default case conversion (full mappings,
// locale-independent; spec M4d1 §5).

///|
/// The General_Category values case conversion needs, by the ordinals of
/// `@general_category.lookup_general_category` (UAX #44 order: Lu 0, Ll 1,
/// Lt 2, Lm 3, Lo 4, Mn 5, Mc 6, Me 7, ..., Sk 23, ..., Cf 26).
priv enum CaseCategory {
  Lt
  Lm
  Mn
  Me
  Sk
  Cf
}

///|
fn case_category(c : Char) -> CaseCategory? {
  match @general_category.lookup_general_category(c) {
    2 => Some(Lt)
    3 => Some(Lm)
    5 => Some(Mn)
    7 => Some(Me)
    23 => Some(Sk)
    26 => Some(Cf)
    _ => None
  }
}

///|
/// Word_Break MidLetter, MidNumLet and Single_Quote (WordBreakProperty.txt,
/// Unicode 18.0.0).
let word_break_mid : Array[Char] = [
  '\u{0027}', '\u{002E}', '\u{003A}', '\u{00B7}', '\u{0387}', '\u{055F}', '\u{05F4}',
  '\u{2018}', '\u{2019}', '\u{2024}', '\u{2027}', '\u{FE13}', '\u{FE52}', '\u{FE55}',
  '\u{FF07}', '\u{FF0E}', '\u{FF1A}',
]

///|
/// Cased (Unicode 3.13): Lowercase, Uppercase or General_Category Lt.
fn is_cased(c : Char) -> Bool {
  @lowercase.is_lowercase(c) ||
  @uppercase.is_uppercase(c) ||
  case_category(c) is Some(Lt)
}

///|
/// Case_Ignorable (Unicode 3.13).
fn is_case_ignorable(c : Char) -> Bool {
  case_category(c) is Some(Mn | Me | Cf | Lm | Sk) || word_break_mid.contains(c)
}

///|
/// Whether a cased letter is reached from `at` by stepping `step` (-1 or +1)
/// over case-ignorable characters only.
fn cased_near(cs : Array[Char], at : Int32, step : Int32) -> Bool {
  let mut i = at + step
  while i >= 0 && i < cs.length() {
    if is_cased(cs[i]) {
      return true
    }
    if !is_case_ignorable(cs[i]) {
      return false
    }
    i += step
  }
  false
}

///|
/// `UPPER(s)`.
pub fn upper(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  apply("UPPER", [Text], args, xs => {
    match xs {
      [String(v)] => {
        let b = StringBuilder()
        for c in v {
          b.write_string(@case_mapping.full_uppercase(c))
        }
        String(b.to_string())
      }
      _ => raise TypeFailure("UPPER of a value that is not a string")
    }
  })
}

///|
/// `LOWER(s)`, with the Final_Sigma context: U+03A3 becomes U+03C2 after a
/// cased letter and not before one (case-ignorable characters skipped).
pub fn lower(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  apply("LOWER", [Text], args, xs => {
    match xs {
      [String(v)] => {
        let cs = chars_of(v)
        let b = StringBuilder()
        for i, c in cs {
          if c == '\u{03A3}' {
            let final_ = cased_near(cs, i, -1) && !cased_near(cs, i, 1)
            b.write_char(if final_ { '\u{03C2}' } else { '\u{03C3}' })
          } else {
            b.write_string(@case_mapping.full_lowercase(c))
          }
        }
        String(b.to_string())
      }
      _ => raise TypeFailure("LOWER of a value that is not a string")
    }
  })
}
