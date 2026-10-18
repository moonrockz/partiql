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
      check_qualifier(q, span)
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
let max_depth : Int32 = 200

///|
fn lower_all(
  items : Array[@ast.Expr],
  scope : Scope,
  depth : Int32,
) -> Array[@plan.Expr] raise @plan.EvalError {
  items.map(item => lower_at(item, scope, depth))
}

///|
fn lower_pairs(
  pairs : Array[(@ast.Expr, @ast.Expr)],
  scope : Scope,
  depth : Int32,
) -> Array[(@plan.Expr, @plan.Expr)] raise @plan.EvalError {
  pairs.map(pair => {
    (lower_at(pair.0, scope, depth), lower_at(pair.1, scope, depth))
  })
}

///|
fn lower_step(
  s : @ast.PathStep,
  scope : Scope,
  depth : Int32,
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
  BinaryLink(@ast.BinaryOp, @ast.Expr, @ast.Expr, @ast.Span)
  AndLink(@ast.Expr, @ast.Span)
  OrLink(@ast.Expr, @ast.Span)
}

///|
/// A chain of binary operators, AND and OR, lowered in a loop down its left
/// spine: `1 + 1 + ... + 1` is as deep as it is long.
fn lower_chain(
  e : @ast.Expr,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  let links : Array[Link] = []
  let nodes : Array[@ast.Expr] = []
  let mut leaf = e
  while true {
    match leaf.kind {
      Binary(_, _, _) | And(_, _) | Or(_, _) => nodes.push(leaf)
      _ => ()
    }
    match leaf.kind {
      Binary(op, l, r) => {
        links.push(BinaryLink(op, l, r, leaf.span))
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
  // The outermost link that is a key ends the chain (`t.a + 1 + 1` finds
  // the key `t.a + 1`). A link is compared only with a key whose spine has
  // as many links, so the search is linear.
  let mut key : String? = None
  if key_context(scope) is Some(context) {
    for j, node in nodes {
      let length = nodes.length() - j
      if context.grouped.keys.iter().any(k => k.links == length) &&
        context.find(node, length) is Some(name) {
        key = Some(name)
        links.truncate(j)
        break
      }
    }
  }
  // Only the innermost link has a query as its left operand; one that is
  // compared with an array literal is coerced (plan ruling 9).
  let leaf_is_row = match links.last() {
    Some(BinaryLink(op, l, r, _)) =>
      key is None &&
      is_comparison(op) &&
      is_select_items(l) &&
      is_array_literal(r)
    _ => false
  }
  let mut result = match key {
    Some(name) => {
      let node = nodes[links.length()]
      keyed(node, Local(name, node.span), scope, depth)
    }
    None =>
      if leaf_is_row {
        row_at(leaf, scope, depth)
      } else {
        lower_at(leaf, scope, depth)
      }
  }
  for link in links.rev_iter() {
    result = match link {
      BinaryLink(op, l, r, span) => {
        let right = if is_comparison(op) &&
          is_array_literal(l) &&
          is_select_items(r) {
          row_at(r, scope, depth)
        } else {
          lower_at(r, scope, depth)
        }
        Binary(op, result, right, span)
      }
      AndLink(r, span) => And(result, lower_at(r, scope, depth), span)
      OrLink(r, span) => Or(result, lower_at(r, scope, depth), span)
    }
  }
  result
}

///|
/// Lowers an expression.
pub fn lower(e : @ast.Expr) -> @plan.Expr raise @plan.EvalError {
  within_depth(lower_plain(e, Scope::top(), 0))
}

///|
/// Lowers an expression `depth` levels down; deeper than `max_depth` is a
/// `DataError`.
fn lower_at(
  e : @ast.Expr,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  let span = e.span
  if depth >= max_depth {
    raise DataError(message="expression is too deep", span~)
  }
  let depth = depth + 1
  // A chain is matched in `lower_chain`, link by link.
  if !(e.kind is (Binary(_, _, _) | And(_, _) | Or(_, _))) &&
    key_variable(e, scope) is Some(name) {
    return keyed(e, Local(name, span), scope, depth)
  }
  match e.kind {
    Lit(l) => Const(literal(l, span), span)
    VarRef(id, qualified~) =>
      match
        scope.resolve(id, defer_ambiguity=scope.globals_first && !qualified) {
        Some((Bound(name), is_with)) =>
          if scope.globals_first && !qualified && !is_with {
            GlobalOrLocal(
              id.text,
              variable=Bound(name),
              delimited=id.delimited,
              span,
            )
          } else {
            Local(name, span)
          }
        Some((Ambiguous(_) as variable, _)) =>
          GlobalOrLocal(id.text, variable~, delimited=id.delimited, span)
        None =>
          if scope.aggregates is Allowed(g) &&
            g.hidden.iter().any(name => names_variable(id, name)) {
            // Spec section 11.2: after grouping, a FROM or LET variable that
            // is not a key is out of scope outside an aggregate.
            raise DataError(
              message="\{id.text} is not a GROUP BY key; use it inside an aggregate function or group by it",
              span~,
            )
          } else if scope.outer is None {
            Global(id.text, delimited=id.delimited, span)
          } else if qualified {
            // Inside a query `@x` names a FROM variable only.
            raise DataError(message="undefined variable @\{id.text}", span~)
          } else if scope.locals() is [] && !(scope.aggregates is Allowed(_)) {
            Global(id.text, delimited=id.delimited, span)
          } else {
            // After grouping, a name that is not a key or GROUP AS (a FROM
            // variable outside an aggregate, or no variable at all) is
            // undefined like any other: MISSING in permissive mode, a
            // TypeError in strict mode (partiql-tests group-by.ion).
            Implicit(
              id.text,
              delimited=id.delimited,
              locals=scope.locals(),
              span,
            )
          }
      }
    // Spec M4a §5: a sexp and a row are lists.
    List(items) | Sexp(items) | Row(items) =>
      ListOf(lower_all(items, scope, depth), span)
    Bag(items) => BagOf(lower_all(items, scope, depth), span)
    Struct(fields) => TupleOf(lower_pairs(fields, scope, depth), span)
    Map(entries) =>
      MapOf(
        lower_pairs(entries, scope, depth),
        key_type=declared_type(entries.map(e => e.0)),
        value_type=declared_type(entries.map(e => e.1)),
        span,
      )
    Query(q) => {
      let inner = query_at(q, scope, depth)
      if is_single_column(e) {
        Subquery(inner, Scalar, span)
      } else {
        inner
      }
    }
    Values(rows) => BagOf(lower_all(rows, scope, depth), span)
    GraphMatch(_) => unsupported("graph MATCH (later)", span)
    Parameter => unsupported("a parameter (later)", span)
    CurrentDatetime(kind, precision~) => {
      let f : @plan.Function = match kind {
        Date => CurrentDate
        Time => CurrentTime(clock_precision(precision, 0, span))
        Timestamp => CurrentTimestamp(clock_precision(precision, 6, span))
      }
      Call(f, [], span)
    }
    Error => raise DataError(message="a broken expression", span~)
    Path(base, steps) =>
      match key_prefix(base, steps, span, scope) {
        Some((name, n)) =>
          Path(
            keyed(
              { kind: Path(base, Array::from_iter(steps[0:n].iter())), span, },
              Local(name, span),
              scope,
              depth,
            ),
            Array::from_iter(steps[n:].iter()).map(s => {
              lower_step(s, scope, depth)
            }),
            span,
          )
        None =>
          Path(
            lower_at(base, scope, depth),
            steps.map(s => lower_step(s, scope, depth)),
            span,
          )
      }
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
      In(lower_at(x, scope, depth), column_at(c, scope, depth), negated~, span)
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
    Coalesce(items) => Coalesce(items.map(x => lower_at(x, scope, depth)), span)
    NullIf(a, b) =>
      NullIf(lower_at(a, scope, depth), lower_at(b, scope, depth), span)
    Trim(spec~, chars~, x) =>
      special_call(
        Trim(spec.unwrap_or(Both)),
        optional(chars) + [x],
        scope,
        depth,
        span,
      )
    Substring(x, start~, length~) =>
      special_call(Substring, [x, start] + optional(length), scope, depth, span)
    Position(needle, hay) =>
      special_call(Position, [needle, hay], scope, depth, span)
    Overlay(x, placing~, from~, for_~) =>
      special_call(
        Overlay,
        [x, placing, from] + optional(for_),
        scope,
        depth,
        span,
      )
    Cast(x, t) => Cast(lower_at(x, scope, depth), target(t, span), span)
    Extract(f, x) => special_call(Extract(f), [x], scope, depth, span)
    DateAdd(f, n, x) => {
      check_date_part(f, "DATE_ADD", span)
      special_call(DateAdd(f), [n, x], scope, depth, span)
    }
    DateDiff(f, a, b) => {
      check_date_part(f, "DATE_DIFF", span)
      special_call(DateDiff(f), [a, b], scope, depth, span)
    }
    Overlaps(x, y) => special_call(Overlaps, [x, y], scope, depth, span)
    Call(id, args, quantifier~) =>
      match aggregate_function(id) {
        Some((kind, true)) =>
          coll_call(kind, id, args, quantifier, scope, depth, span)
        Some((_, false)) => sql_aggregate_call(e, scope, depth)
        None =>
          match builtin(id) {
            Some((f, arity)) =>
              scalar_call(f, arity, args, quantifier, scope, depth, span)
            None => raise unknown_function(id)
          }
      }
    CallStar(id) =>
      match aggregate_function(id) {
        Some((_, true)) =>
          raise DataError(message="\{id.text} does not take *", span~)
        Some((_, false)) => sql_aggregate_call(e, scope, depth)
        None =>
          match builtin(id) {
            Some((f, _)) =>
              raise DataError(message="\{f.name()} does not take *", span~)
            None => raise unknown_function(id)
          }
      }
  }
}

///|
fn is_comparison(op : @ast.BinaryOp) -> Bool {
  match op {
    Eq | Ne | Lt | Le | Gt | Ge => true
    _ => false
  }
}

///|
fn is_array_literal(e : @ast.Expr) -> Bool {
  match e.kind {
    List(_) | Sexp(_) | Row(_) => true
    // A backtick Ion list or s-expression without annotations (an annotation
    // such as `$bag` changes the kind of the value).
    Lit(Ion(_, v)) => !v.has_annotations() && v.kind() is (List(_) | Sexp(_))
    _ => false
  }
}
