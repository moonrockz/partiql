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
fn[T] unsupported(form : String, span : @ast.Span) -> T raise @plan.EvalError {
  raise Unsupported(message="\{form} is not supported yet", span~)
}

///|
/// Whether a MAP key or value type has no parameter: a map declares its types
/// by name only (`MapType`), so a parameter could not be checked.
fn plain_map_type(t : @ast.DataType) -> Bool {
  match t {
    Decimal(None, None)
    | Numeric(None, None)
    | Double(None)
    | Char(None)
    | Varchar(None)
    | Time(None, with_tz=false)
    | Timestamp(None, with_tz=false) => true
    Decimal(_, _)
    | Numeric(_, _)
    | Double(_)
    | Char(_)
    | Varchar(_)
    | Time(_, ..)
    | Timestamp(_, ..)
    | Interval(_)
    | Map(_, _)
    | Array(_) => false
    _ => true
  }
}

///|
/// The type of `x IS type`. A parameter that the type test does not check is
/// `Unsupported` (ignoring it would give a wrong answer); an interval
/// qualifier that is not valid is a `DataError`.
fn type_test(
  t : @ast.DataType,
  span : @ast.Span,
) -> @ast.DataType raise @plan.EvalError {
  match t {
    Double(Some(_)) =>
      raise Unsupported(message="IS FLOAT(p) is not supported yet", span~)
    Array(Some(_)) =>
      raise Unsupported(
        message="IS ARRAY with an element type is not supported yet",
        span~,
      )
    Map(k, v) if !plain_map_type(k) || !plain_map_type(v) =>
      raise Unsupported(
        message="IS MAP with a type parameter in the key or value type is not supported yet",
        span~,
      )
    Interval(q) => {
      ignore(interval_fields(q)) catch {
        _ =>
          raise DataError(
            message="an interval qualifier that is not valid",
            span~,
          )
      }
      if q.fractional_precision is Some(f) && (f < 0 || f > 9) {
        raise DataError(message="a fractional precision out of range", span~)
      }
      if q.start_precision is Some(p) && p < 1 {
        raise DataError(message="a leading precision out of range", span~)
      }
      t
    }
    _ => t
  }
}

///|
/// The deepest nesting that lowering accepts. The parser limits parentheses
/// and prefix operators, but not postfix chains such as `x IS NULL IS NULL`.
/// Lowering stops at this depth, which keeps its own recursion off the end
/// of the stack; `within_depth` (depth.mbt) then bounds the nesting of the
/// plan when it runs. Left-associative operator chains do not count: they
/// are lowered and run in a loop.
let max_depth : Int = 200

///|
fn lower_all(
  items : Array[@ast.Expr],
  scope : Scope,
  depth : Int,
) -> Array[@plan.Expr] raise @plan.EvalError {
  items.map(item => lower_at(item, scope, depth))
}

///|
fn lower_pairs(
  pairs : Array[(@ast.Expr, @ast.Expr)],
  scope : Scope,
  depth : Int,
) -> Array[(@plan.Expr, @plan.Expr)] raise @plan.EvalError {
  pairs.map(pair => {
    (lower_at(pair.0, scope, depth), lower_at(pair.1, scope, depth))
  })
}

///|
fn lower_step(
  s : @ast.PathStep,
  scope : Scope,
  depth : Int,
) -> @plan.Step raise @plan.EvalError {
  match s {
    Field(id) => Field(id.text, delimited=id.delimited)
    FieldString(name, ..) => Field(name, delimited=true)
    Index(e) => Index(lower_at(e, scope, depth))
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
fn lower_chain(
  e : @ast.Expr,
  scope : Scope,
  depth : Int,
) -> @plan.Expr raise @plan.EvalError {
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
  let mut result = lower_at(leaf, scope, depth)
  for link in links.rev_iter() {
    result = match link {
      BinaryLink(op, r, span) =>
        Binary(op, result, lower_at(r, scope, depth), span)
      AndLink(r, span) => And(result, lower_at(r, scope, depth), span)
      OrLink(r, span) => Or(result, lower_at(r, scope, depth), span)
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
  within_depth(lower_at(e, Scope::top(), 0))
}

///|
/// Lowers an expression `depth` levels down; deeper than `max_depth` is a
/// `DataError`.
fn lower_at(
  e : @ast.Expr,
  scope : Scope,
  depth : Int,
) -> @plan.Expr raise @plan.EvalError {
  let span = e.span
  if depth >= max_depth {
    raise DataError(message="expression is too deep", span~)
  }
  let depth = depth + 1
  match e.kind {
    Lit(Ion(_, v)) if depth + ion_depth(v) > max_depth =>
      raise DataError(message="expression is too deep", span~)
    Lit(l) => Const(literal(l, span), span)
    VarRef(id, qualified~) =>
      match scope.resolve(id) {
        Some(name) =>
          if scope.globals_first && !qualified {
            GlobalOrLocal(id.text, variable=name, delimited=id.delimited, span)
          } else {
            Local(name, span)
          }
        None =>
          match scope.locals() {
            [] => Global(id.text, delimited=id.delimited, span)
            locals =>
              if qualified {
                raise DataError(message="undefined variable @\{id.text}", span~)
              } else {
                Implicit(id.text, delimited=id.delimited, locals~, span)
              }
          }
      }
    // Spec M4a §5: a sexp and a row are lists.
    List(items) | Sexp(items) | Row(items) =>
      ListOf(lower_all(items, scope, depth), span)
    Bag(items) => BagOf(lower_all(items, scope, depth), span)
    Struct(fields) => TupleOf(lower_pairs(fields, scope, depth), span)
    Map(entries) => MapOf(lower_pairs(entries, scope, depth), span)
    Query(q) => query_at(q, scope, depth)
    Values(_) => unsupported("VALUES (M4b)", span)
    GraphMatch(_) => unsupported("graph MATCH (later)", span)
    Parameter => unsupported("a parameter (later)", span)
    Error => raise DataError(message="a broken expression", span~)
    Path(base, steps) =>
      Path(
        lower_at(base, scope, depth),
        steps.map(s => lower_step(s, scope, depth)),
        span,
      )
    // `-9223372036854775808` is a literal: its magnitude is out of range.
    Unary(Neg, { kind: Lit(Int(text)), .. }) =>
      Const(integer_value("-" + text, span), span)
    Unary(op, x) => Unary(op, lower_at(x, scope, depth), span)
    Binary(_, _, _) | And(_, _) | Or(_, _) => lower_chain(e, scope, depth)
    Not(x) => Not(lower_at(x, scope, depth), span)
    BoolTest(x, truth, negated~) =>
      BoolTest(lower_at(x, scope, depth), truth, negated~, span)
    Like(x, pattern~, escape~, negated~) =>
      Like(
        lower_at(x, scope, depth),
        pattern=lower_at(pattern, scope, depth),
        escape=escape.map(x => lower_at(x, scope, depth)),
        negated~,
        span,
      )
    Between(x, low~, high~, negated~) =>
      Between(
        lower_at(x, scope, depth),
        low=lower_at(low, scope, depth),
        high=lower_at(high, scope, depth),
        negated~,
        span,
      )
    In(x, c, negated~) =>
      In(lower_at(x, scope, depth), lower_at(c, scope, depth), negated~, span)
    IsNull(x, negated~) => IsNull(lower_at(x, scope, depth), negated~, span)
    IsMissing(x, negated~) =>
      IsMissing(lower_at(x, scope, depth), negated~, span)
    IsType(x, t, negated~) =>
      IsType(lower_at(x, scope, depth), type_test(t, span), negated~, span)
    Case(operand~, branches~, default~) =>
      Case(
        operand=operand.map(x => lower_at(x, scope, depth)),
        branches=branches.map(b => {
          (lower_at(b.0, scope, depth), lower_at(b.1, scope, depth))
        }),
        default=default.map(x => lower_at(x, scope, depth)),
        span,
      )
    Coalesce(items) => Coalesce(lower_all(items, scope, depth), span)
    NullIf(a, b) =>
      NullIf(lower_at(a, scope, depth), lower_at(b, scope, depth), span)
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
