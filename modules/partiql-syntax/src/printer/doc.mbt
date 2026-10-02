// The document algebra (Wadler/Leijen style). The printer builds a Doc; a
// renderer lays it out: `render_flat` gives the canonical one-line text,
// `render` the pretty layout at a width through `moonrockz/pretty` (spec M3b).

///|
priv enum Doc {
  Nil
  Text(String)
  /// A space when flat; a line break when its group breaks.
  Line
  /// Nothing when flat; a line break when its group breaks.
  SoftLine
  /// Always a line break.
  HardLine
  Concat(Doc, Doc)
  /// Indents the broken lines of the document by `n` more.
  Nest(Int, Doc)
  /// Flat when it fits the width, else broken (pretty layout only).
  Group(Doc)
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
/// The docs that are not `Nil`, separated by one space (never a break).
fn spaced(docs : Array[Doc]) -> Doc {
  sep(docs.filter(d => !(d is Nil)), " ")
}

///|
/// The docs that are not `Nil`, separated by `Line`.
fn lines(docs : Array[Doc]) -> Doc {
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
/// The canonical rendering: groups and nests are ignored, `Line` is a space,
/// `SoftLine` is nothing. Iterative, so deep documents cannot overflow the
/// stack.
fn render_flat(doc : Doc) -> String {
  let buf = StringBuilder()
  let stack : Array[Doc] = [doc]
  while stack.pop() is Some(d) {
    match d {
      Nil | SoftLine => ()
      Text(s) => buf.write_string(s)
      Line => buf.write_char(' ')
      HardLine => buf.write_char('\n')
      Concat(a, b) => {
        stack.push(b)
        stack.push(a)
      }
      Nest(_, x) | Group(x) => stack.push(x)
    }
  }
  buf.to_string()
}

///|
priv enum Step {
  Visit(Doc)
  Join
  WrapNest(Int)
  WrapGroup
}

///|
/// The same document for `@pretty`, built with an explicit stack.
fn to_pretty(root : Doc) -> @pretty.Doc {
  let steps : Array[Step] = [Visit(root)]
  let out : Array[@pretty.Doc] = []
  while steps.pop() is Some(step) {
    match step {
      Visit(Nil) => out.push(@pretty.empty())
      Visit(Text(s)) => out.push(@pretty.text(s))
      Visit(Line) => out.push(@pretty.line())
      Visit(SoftLine) => out.push(@pretty.softline())
      Visit(HardLine) => out.push(@pretty.hardline())
      Visit(Concat(a, b)) => {
        steps.push(Join)
        steps.push(Visit(b))
        steps.push(Visit(a))
      }
      Visit(Nest(n, d)) => {
        steps.push(WrapNest(n))
        steps.push(Visit(d))
      }
      Visit(Group(d)) => {
        steps.push(WrapGroup)
        steps.push(Visit(d))
      }
      Join =>
        if out.pop() is Some(b) && out.pop() is Some(a) {
          out.push(a + b)
        }
      WrapNest(n) => if out.pop() is Some(d) { out.push(@pretty.nest(n, d)) }
      WrapGroup => if out.pop() is Some(d) { out.push(@pretty.group(d)) }
    }
  }
  out.pop().unwrap_or(@pretty.empty())
}

///|
/// The pretty layout at `width` (a width below 1 counts as 1). The whole
/// document is one group, so a line break outside every group breaks only
/// when the document does not fit.
fn render(doc : Doc, width : Int) -> String {
  @pretty.render(
    @pretty.group(to_pretty(doc)),
    width=if width < 1 { 1 } else { width },
  )
}

///|
/// Items separated by `,` and a breakable space.
fn break_items(items : Array[Doc]) -> Doc {
  let out : Array[Doc] = []
  for i, d in items {
    if i > 0 {
      out.push(Text(","))
      out.push(Line)
    }
    out.push(d)
  }
  cat(out)
}

///|
/// `KEYWORD items`: the items stay after the keyword when they fit, else each
/// item is on its own line, indented by 2.
fn list_clause(keyword : String, items : Array[Doc]) -> Doc {
  Group(cat([Text(keyword), Nest(2, cat([Line, break_items(items)]))]))
}

///|
/// `(d)`; broken, `d` starts on the next line indented by 2 and `)` closes on
/// its own line.
fn sub(d : Doc) -> Doc {
  Group(cat([Text("("), Nest(2, cat([SoftLine, d])), SoftLine, Text(")")]))
}
