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
/// The deepest nesting that lowering accepts. The parser limits parentheses
/// and prefix operators, but not postfix chains such as `x IS NULL IS NULL`;
/// this limit keeps every recursion here and in the interpreter off the end
/// of the stack. Left-associative operator chains do not count: they are
/// lowered and run in a loop.
let max_depth : Int = 200

///|
fn lower_all(
  items : Array[@ast.Expr],
  depth : Int,
) -> Array[@plan.Expr] raise @plan.EvalError {
  items.map(item => lower_at(item, depth))
}

///|
fn lower_pairs(
  pairs : Array[(@ast.Expr, @ast.Expr)],
  depth : Int,
) -> Array[(@plan.Expr, @plan.Expr)] raise @plan.EvalError {
  pairs.map(pair => (lower_at(pair.0, depth), lower_at(pair.1, depth)))
}

///|
fn lower_step(
  s : @ast.PathStep,
  depth : Int,
) -> @plan.Step raise @plan.EvalError {
  match s {
    Field(id) => Field(id.text, delimited=id.delimited)
    FieldString(name, ..) => Field(name, delimited=true)
    Index(e) => Index(lower_at(e, depth))
    AllElements(_) => AllElements
    AllFields(_) => AllFields
  }
}

///|
/// One link of a left-associative chain: the operator, its right operand and
/// the span of the whole link.
priv enum Link {
  BinaryLink(@ast.BinaryOp, @ast.Expr, @ast.Span)
  AndLink(@ast.Expr, @ast.Span)
  OrLink(@ast.Expr, @ast.Span)
}

///|
/// A chain of binary operators, AND and OR, lowered in a loop down its left
/// spine: `1 + 1 + ... + 1` is as deep as it is long.
fn lower_chain(e : @ast.Expr, depth : Int) -> @plan.Expr raise @plan.EvalError {
  let links : Array[Link] = []
  let mut leaf = e
  while true {
    match leaf.kind {
      Binary(op, l, r) => {
        links.push(BinaryLink(op, r, leaf.span))
        leaf = l
      }
      And(l, r) => {
        links.push(AndLink(r, leaf.span))
        leaf = l
      }
      Or(l, r) => {
        links.push(OrLink(r, leaf.span))
        leaf = l
      }
      _ => break
    }
  }
  let mut result = lower_at(leaf, depth)
  for link in links.rev_iter() {
    result = match link {
      BinaryLink(op, r, span) => Binary(op, result, lower_at(r, depth), span)
      AndLink(r, span) => And(result, lower_at(r, depth), span)
      OrLink(r, span) => Or(result, lower_at(r, depth), span)
    }
  }
  result
}

///|
/// The nesting depth of an Ion value (a scalar is 1), counted in a loop: the
/// parser does not limit the depth of an Ion literal.
fn ion_depth(v : @ion_core.IonValue) -> Int {
  let mut deepest = 0
  let pending = [(v, 1)]
  while pending.pop() is Some((x, d)) {
    deepest = deepest.max(d)
    match x.kind() {
      List(items) | Sexp(items) =>
        for item in items {
          pending.push((item, d + 1))
        }
      Struct(fields) =>
        for field in fields {
          pending.push((field.value(), d + 1))
        }
      _ => ()
    }
  }
  deepest
}

///|
/// Lowers an expression.
pub fn lower(e : @ast.Expr) -> @plan.Expr raise @plan.EvalError {
  lower_at(e, 0)
}

///|
/// Lowers an expression `depth` levels down; deeper than `max_depth` is a
/// `DataError`.
fn lower_at(e : @ast.Expr, depth : Int) -> @plan.Expr raise @plan.EvalError {
  let span = e.span
  if depth >= max_depth {
    raise DataError(message="expression is too deep", span~)
  }
  let depth = depth + 1
  match e.kind {
    Lit(Ion(_, v)) if depth + ion_depth(v) > max_depth =>
      raise DataError(message="expression is too deep", span~)
    Lit(l) => Const(literal(l, span), span)
    VarRef(id, qualified=_) => Global(id.text, delimited=id.delimited, span)
    // Spec M4a §5: a sexp and a row are lists.
    List(items) | Sexp(items) | Row(items) =>
      ListOf(lower_all(items, depth), span)
    Bag(items) => BagOf(lower_all(items, depth), span)
    Struct(fields) => TupleOf(lower_pairs(fields, depth), span)
    Map(entries) => MapOf(lower_pairs(entries, depth), span)
    Query(_) => unsupported("a subquery (M4b)", span)
    Values(_) => unsupported("VALUES (M4b)", span)
    GraphMatch(_) => unsupported("graph MATCH (later)", span)
    Parameter => unsupported("a parameter (later)", span)
    Error => raise DataError(message="a broken expression", span~)
    Path(base, steps) =>
      Path(lower_at(base, depth), steps.map(s => lower_step(s, depth)), span)
    // `-9223372036854775808` is a literal: its magnitude is out of range.
    Unary(Neg, { kind: Lit(Int(text)), .. }) =>
      Const(integer_value("-" + text, span), span)
    Unary(op, x) => Unary(op, lower_at(x, depth), span)
    Binary(_, _, _) | And(_, _) | Or(_, _) => lower_chain(e, depth)
    Not(x) => Not(lower_at(x, depth), span)
    BoolTest(x, truth, negated~) =>
      BoolTest(lower_at(x, depth), truth, negated~, span)
    Like(x, pattern~, escape~, negated~) =>
      Like(
        lower_at(x, depth),
        pattern=lower_at(pattern, depth),
        escape=escape.map(x => lower_at(x, depth)),
        negated~,
        span,
      )
    Between(x, low~, high~, negated~) =>
      Between(
        lower_at(x, depth),
        low=lower_at(low, depth),
        high=lower_at(high, depth),
        negated~,
        span,
      )
    In(x, c, negated~) =>
      In(lower_at(x, depth), lower_at(c, depth), negated~, span)
    IsNull(x, negated~) => IsNull(lower_at(x, depth), negated~, span)
    IsMissing(x, negated~) => IsMissing(lower_at(x, depth), negated~, span)
    IsType(x, t, negated~) => IsType(lower_at(x, depth), t, negated~, span)
    Case(operand~, branches~, default~) =>
      Case(
        operand=operand.map(x => lower_at(x, depth)),
        branches=branches.map(b => (lower_at(b.0, depth), lower_at(b.1, depth))),
        default=default.map(x => lower_at(x, depth)),
        span,
      )
    Coalesce(items) => Coalesce(lower_all(items, depth), span)
    NullIf(a, b) => NullIf(lower_at(a, depth), lower_at(b, depth), span)
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
