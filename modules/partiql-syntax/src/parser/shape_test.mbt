// Test support: syntax tree shapes, now the public S-expression format.

///|
let flat : Int = 1_000_000_000

///|
fn shape(e : @ast.Expr) -> String {
  @sexp.expr_to_sexp(e, width=flat)
}

///|
fn query_shape(q : @ast.Query) -> String {
  @sexp.query_to_sexp(q, width=flat)
}

///|
fn statement_shape(source : String) -> String raise {
  @sexp.to_sexp(@parser.parse_statement(source), width=flat)
}

///|
fn expr_shape(source : String) -> String raise {
  shape(@parser.parse_expression(source))
}

///|
fn syntax_error(e : Error) -> Bool {
  e is @ast.ParseError::Syntax(_)
}
