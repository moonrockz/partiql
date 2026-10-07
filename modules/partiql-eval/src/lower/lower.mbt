///|
/// An integer literal. One outside Int64 is a `DataError`, in both modes
/// (partiql-tests extended int.ion, `int_overflow_error`).
fn integer_value(
  text : String,
  span : @ast.Span,
) -> @value.Value raise @plan.EvalError {
  let n = @bigint.BigInt::from_string(text)
  if n.compare_int64(9223372036854775807L) > 0 ||
    n.compare_int64(-9223372036854775808L) < 0 {
    raise DataError(message="integer literal \{text} is out of range", span~)
  }
  Int(n.to_int64())
}

///|
fn rounded(
  d : @ion_core.Decimal,
  span : @ast.Span,
) -> @ion_core.Decimal raise @plan.EvalError {
  @ops.round_decimal(d) catch {
    _ => raise DataError(message="decimal literal out of range", span~)
  }
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
    Int(text) => integer_value(text, span)
    Decimal(text) =>
      try @ion_core.Decimal::parse(text) catch {
        _ => raise DataError(message="invalid decimal literal \{text}", span~)
      } noraise {
        d => Decimal(rounded(d, span))
      }
    // A number with an exponent is a decimal in PartiQL.
    Float(text) =>
      match @ops.parse_decimal(text) {
        Some(d) => Decimal(rounded(d, span))
        None => raise DataError(message="invalid float literal \{text}", span~)
      }
    String(s) => String(s)
    Ion(_, v) => @partiql_ion.from_ion_data(v)
    Date(text) => Date(date_literal(text, span~))
    Time(text, precision~, with_tz~) =>
      Time(time_literal(text, precision, with_tz, span~))
    Timestamp(text, precision~, with_tz~) =>
      Timestamp(timestamp_literal(text, precision, with_tz, span~))
    Interval(text, negative~, qualifier~) =>
      interval_literal(text, negative~, qualifier~, span~)
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
fn lower_step(s : @ast.PathStep) -> @plan.Step raise @plan.EvalError {
  match s {
    Field(id) => Field(id.text, delimited=id.delimited)
    FieldString(name, ..) => Field(name, delimited=true)
    Index(e) => Index(lower(e))
    AllElements(_) => AllElements
    AllFields(_) => AllFields
  }
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
    Path(base, steps) => Path(lower(base), steps.map(lower_step), span)
    // `-9223372036854775808` is a literal: its magnitude is out of range.
    Unary(Neg, { kind: Lit(Int(text)), .. }) =>
      Const(integer_value("-" + text, span), span)
    Unary(op, x) => Unary(op, lower(x), span)
    Binary(op, l, r) => Binary(op, lower(l), lower(r), span)
    And(l, r) => And(lower(l), lower(r), span)
    Or(l, r) => Or(lower(l), lower(r), span)
    Not(x) => Not(lower(x), span)
    BoolTest(x, truth, negated~) => BoolTest(lower(x), truth, negated~, span)
    Like(_, ..) => unsupported("LIKE (M4d)", span)
    Between(x, low~, high~, negated~) =>
      Between(lower(x), low=lower(low), high=lower(high), negated~, span)
    In(x, c, negated~) => In(lower(x), lower(c), negated~, span)
    IsNull(x, negated~) => IsNull(lower(x), negated~, span)
    IsMissing(x, negated~) => IsMissing(lower(x), negated~, span)
    IsType(x, t, negated~) => IsType(lower(x), t, negated~, span)
    Case(operand~, branches~, default~) =>
      Case(
        operand=operand.map(lower),
        branches=branches.map(b => (lower(b.0), lower(b.1))),
        default=default.map(lower),
        span,
      )
    Coalesce(items) => Coalesce(lower_all(items), span)
    NullIf(a, b) => NullIf(lower(a), lower(b), span)
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
