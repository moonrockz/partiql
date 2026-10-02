// The printer: a syntax tree to a Doc, with the comments of the source written
// at node boundaries (spec M3a sections 6 and 7).

///|
priv struct Printer {
  comments : Array[@ast.Comment]
  mut next : Int
  /// Print every row as `ROW(..)`: set inside a FROM source, where a
  /// leading `(` would start a parenthesized join.
  mut row_calls : Bool
}

///|
fn Printer::new(comments : Array[@ast.Comment]) -> Printer {
  { comments, next: 0, row_calls: false, }
}

///|
fn comment_doc(c : @ast.Comment) -> Doc {
  match c.kind {
    Line => cat([Text(c.text), HardLine])
    Block => cat([Text(c.text), Text(" ")])
  }
}

///|
/// The comments that end at or before `span` starts, not yet written.
fn Printer::leading(self : Printer, span : @ast.Span) -> Doc {
  let docs : Array[Doc] = []
  while self.next < self.comments.length() &&
        self.comments[self.next].span.end <= span.start {
    docs.push(comment_doc(self.comments[self.next]))
    self.next += 1
  }
  cat(docs)
}

///|
/// Whether a comment is pending before `span`.
fn Printer::pending(self : Printer, span : @ast.Span) -> Bool {
  self.next < self.comments.length() &&
  self.comments[self.next].span.end <= span.start
}

///|
fn Printer::statement(self : Printer, s : @ast.Statement) -> Doc {
  match s {
    Query(q) => self.query(q)
  }
}

///|
/// The canonical text of a statement, without comments.
pub fn print(statement : @ast.Statement) -> String {
  render_flat(Printer::new([]).statement(statement))
}

///|
fn statement_span(s : @ast.Statement) -> @ast.Span {
  match s {
    Query(q) => q.span
  }
}

///|
/// Pending comments before `span`, each on its own line.
fn Printer::own_lines(self : Printer, span : @ast.Span) -> Doc {
  let docs : Array[Doc] = []
  while self.pending(span) {
    docs.push(Text(self.comments[self.next].text))
    docs.push(HardLine)
    self.next += 1
  }
  cat(docs)
}

///|
/// The canonical text of a script: each statement on its own line followed by
/// `;`, with the script's comments (spec M3a section 7).
pub fn print_script(script : @ast.Script) -> String {
  let p = Printer::new(script.comments)
  let docs : Array[Doc] = []
  for s in script.statements {
    docs.push(p.own_lines(statement_span(s)))
    docs.push(p.statement(s))
    docs.push(Text(";"))
    docs.push(HardLine)
  }
  docs.push(
    p.own_lines({ start: script.span.end + 1, end: script.span.end + 1, }),
  )
  render_flat(cat(docs))
}
