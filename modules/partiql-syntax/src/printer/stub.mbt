///|
fn Printer::query(self : Printer, q : @ast.Query) -> Doc {
  ignore(self)
  match q.body {
    Expr(e) => Printer::new([]).expr(e)
    _ => Text("(query)")
  }
}

///|
fn Printer::graph(self : Printer, m : @ast.GraphMatch) -> Doc {
  ignore((self, m))
  Text("(graph)")
}
