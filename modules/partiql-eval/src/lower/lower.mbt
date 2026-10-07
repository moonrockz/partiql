///|
fn integer_value(text : String) -> @value.Value {
  @value.Value::integer(@bigint.BigInt::from_string(text))
}

///|
fn literal(
  l : @ast.Literal,
  span : @ast.Span,
) -> @value.Value raise @plan.EvalError {
  match l {
    Null => Null
    Missing => Missing
    Bool(b) => Bool(b)
    Int(text) => integer_value(text)
    Decimal(text) =>
      try @ion_core.Decimal::parse(text) catch {
        _ => raise DataError(message="invalid decimal literal \{text}", span~)
      } noraise {
        d => Decimal(d)
      }
    Float(text) =>
      try @string.parse_double(text) catch {
        _ => raise DataError(message="invalid float literal \{text}", span~)
      } noraise {
        d => Float(d)
      }
    String(s) => String(s)
    Ion(_, v) => @partiql_ion.from_ion_data(v)
    Date(_) | Time(_, ..) | Timestamp(_, ..) | Interval(_, ..) =>
      raise Unsupported(message="datetime literals (M4a task 5)", span~)
  }
}

///|
fn unsupported(
  form : String,
  span : @ast.Span,
) -> @plan.Expr raise @plan.EvalError {
  raise Unsupported(message="\{form} is not supported yet", span~)
}

///|
fn lower_all(
  items : Array[@ast.Expr],
) -> Array[@plan.Expr] raise @plan.EvalError {
  items.map(lower)
}

///|
fn lower_pairs(
  pairs : Array[(@ast.Expr, @ast.Expr)],
) -> Array[(@plan.Expr, @plan.Expr)] raise @plan.EvalError {
  pairs.map(pair => (lower(pair.0), lower(pair.1)))
}

///|
/// Lowers an expression. Recursion is safe: the parser rejects input nested
/// deeper than its limit.
pub fn lower(e : @ast.Expr) -> @plan.Expr raise @plan.EvalError {
  let span = e.span
  match e.kind {
    Lit(l) => Const(literal(l, span), span)
    VarRef(id, qualified=_) => Global(id.text, delimited=id.delimited, span)
    // Spec M4a §5: a sexp and a row are lists.
    List(items) | Sexp(items) | Row(items) => ListOf(lower_all(items), span)
    Bag(items) => BagOf(lower_all(items), span)
    Struct(fields) => TupleOf(lower_pairs(fields), span)
    Map(entries) => MapOf(lower_pairs(entries), span)
    Query(_) => unsupported("a subquery (M4b)", span)
    Values(_) => unsupported("VALUES (M4b)", span)
    GraphMatch(_) => unsupported("graph MATCH (later)", span)
    Parameter => unsupported("a parameter (later)", span)
    Error => raise DataError(message="a broken expression", span~)
    Path(_, _) => unsupported("a path", span)
    Unary(_, _) | Binary(_, _, _) => unsupported("an operator", span)
    And(_, _) | Or(_, _) | Not(_) | BoolTest(_, _, ..) =>
      unsupported("a logical operator", span)
    Like(_, ..) | Between(_, ..) | In(_, _, ..) =>
      unsupported("a predicate", span)
    IsNull(_, ..) | IsMissing(_, ..) | IsType(_, _, ..) =>
      unsupported("an IS test", span)
    Case(..) | Coalesce(_) | NullIf(_, _) => unsupported("a conditional", span)
    Overlaps(_, _)
    | Cast(_, _)
    | Extract(_, _)
    | Trim(_, ..)
    | Substring(_, ..)
    | Position(_, _)
    | Overlay(_, ..)
    | DateAdd(_, _, _)
    | DateDiff(_, _, _)
    | Call(_, _, ..)
    | CallStar(_) => unsupported("a function call (M4d)", span)
  }
}
