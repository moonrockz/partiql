// The document algebra (Wadler/Leijen style). The printer builds a Doc; a
// renderer lays it out. M3a renders flat; M3b adds Nest, Group and a
// width-aware renderer (spec M3a section 5).

///|
priv enum Doc {
  Nil
  Text(String)
  /// A space when flat; a line break when its group breaks (M3b).
  Line
  /// Always a line break.
  HardLine
  Concat(Doc, Doc)
} derive(Debug)

///|
fn cat(docs : Array[Doc]) -> Doc {
  let mut out = Nil
  for d in docs {
    out = match (out, d) {
      (Nil, x) => x
      (x, Nil) => x
      (a, b) => Concat(a, b)
    }
  }
  out
}

///|
fn sep(docs : Array[Doc], separator : String) -> Doc {
  let out : Array[Doc] = []
  for i, d in docs {
    if i > 0 {
      out.push(Text(separator))
    }
    out.push(d)
  }
  cat(out)
}

///|
/// The docs that are not `Nil`, separated by `Line` (a space when flat).
fn spaced(docs : Array[Doc]) -> Doc {
  let out : Array[Doc] = []
  for d in docs {
    if d is Nil {
      continue
    }
    if !out.is_empty() {
      out.push(Line)
    }
    out.push(d)
  }
  cat(out)
}

///|
fn parens(d : Doc) -> Doc {
  cat([Text("("), d, Text(")")])
}

///|
/// Renders every group flat. Iterative, so deep documents cannot overflow
/// the stack.
fn render_flat(doc : Doc) -> String {
  let buf = StringBuilder()
  let stack : Array[Doc] = [doc]
  while stack.pop() is Some(d) {
    match d {
      Nil => ()
      Text(s) => buf.write_string(s)
      Line => buf.write_char(' ')
      HardLine => buf.write_char('\n')
      Concat(a, b) => {
        stack.push(b)
        stack.push(a)
      }
    }
  }
  buf.to_string()
}
