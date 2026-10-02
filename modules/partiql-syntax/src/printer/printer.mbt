// The printer: a syntax tree to a Doc, with the comments of the source written
// at node boundaries (spec M3a sections 6 and 7).

///|
priv struct Printer {
  comments : Array[@ast.Comment]
  mut next : Int
}

///|
fn Printer::new(comments : Array[@ast.Comment]) -> Printer {
  { comments, next: 0, }
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
