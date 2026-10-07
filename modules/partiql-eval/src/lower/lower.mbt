///|
fn integer_value(text : String) -> @value.Value {
  @value.Value::integer(@bigint.BigInt::from_string(text))
}

///|
/// The most digits a PartiQL decimal keeps (spec M4a §5).
let max_decimal_digits : Int = 38

///|
/// Rounds a decimal to 38 significant digits, half to even.
fn round_decimal(d : @ion_core.Decimal) -> @ion_core.Decimal {
  let digits = d.coefficient().to_string()
  let negative = digits.has_prefix("-")
  let magnitude = if negative {
    digits.view(start_offset=1).to_owned()
  } else {
    digits
  }
  let drop = magnitude.length() - max_decimal_digits
  if drop <= 0 {
    return d
  }
  let kept = @bigint.BigInt::from_string(
    magnitude.view(end_offset=max_decimal_digits).to_owned(),
  )
  let rest = magnitude.view(start_offset=max_decimal_digits).to_owned()
  let half = "5" + "0".repeat(drop - 1)
  let up = match rest.lexical_compare(half) {
    -1 => false
    1 => true
    _ => kept % @bigint.BigInt::from_int(2) == @bigint.BigInt::from_int(1)
  }
  let rounded = if up { kept + @bigint.BigInt::from_int(1) } else { kept }
  let signed = if negative { -rounded } else { rounded }
  @ion_core.Decimal::new(signed, d.exponent() + drop)
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
        d => Decimal(round_decimal(d))
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
    Unary(_, _) | Binary(_, _, _) => unsupported("an operator", span)
    And(_, _) | Or(_, _) | Not(_) | BoolTest(_, _, ..) =>
      unsupported("a logical operator", span)
    Like(_, ..) | Between(_, ..) | In(_, _, ..) =>
      unsupported("a predicate", span)
    IsNull(x, negated~) => IsNull(lower(x), negated~, span)
    IsMissing(x, negated~) => IsMissing(lower(x), negated~, span)
    IsType(_, _, ..) => unsupported("an IS type test", span)
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
