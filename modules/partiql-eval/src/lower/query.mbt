///|
/// The variables that FROM and LET declare, in the order they are declared,
/// with the scope of the enclosing query (spec M4b1 §4).
priv struct Scope {
  names : Array[String]
  outer : Scope?
  /// Inside a FROM source, a plain name finds a global before a variable.
  globals_first : Bool
  /// The names are the output names of a SELECT list (for ORDER BY): a name
  /// finds them first, but they are not candidates for an implicit
  /// attribute.
  outputs : Bool
}

///|
/// The scope outside every query: no variables.
fn Scope::top() -> Scope {
  { names: [], outer: None, globals_first: false, outputs: false, }
}

///|
/// A scope inside `self` that declares `names`.
fn Scope::inner(self : Scope, names : Array[String]) -> Scope {
  { names, outer: Some(self), globals_first: false, outputs: false, }
}

///|
/// A scope inside `self` with the output names of a SELECT list.
fn Scope::with_outputs(self : Scope, names : Array[String]) -> Scope {
  { ..self.inner(names), outputs: true, }
}

///|
/// The same scope, for the expression of a FROM source.
fn Scope::for_source(self : Scope) -> Scope {
  { ..self, globals_first: true, }
}

///|
/// The declared name of the innermost variable that `id` names: a regular
/// identifier ignores case, a delimited one does not.
fn Scope::resolve(self : Scope, id : @ast.Identifier) -> String? {
  let wanted = if id.delimited { id.text } else { id.text.to_lower() }
  let mut scope = Some(self)
  while scope is Some(s) {
    for name in s.names.rev_iter() {
      let key = if id.delimited { name } else { name.to_lower() }
      if key == wanted {
        return Some(name)
      }
    }
    scope = s.outer
  }
  None
}

///|
/// The names of every variable in scope, the innermost query first and each
/// query in FROM order. Output names are left out.
fn Scope::locals(self : Scope) -> Array[String] {
  let all = []
  let mut scope = Some(self)
  while scope is Some(s) {
    if !s.outputs {
      all.append(s.names)
    }
    scope = s.outer
  }
  all
}

///|
/// Lowers a query statement.
pub fn lower_query(q : @ast.Query) -> @plan.Expr raise @plan.EvalError {
  within_depth(query_at(q, Scope::top(), 0))
}

///|
/// Lowers a query `depth` levels down. A form that a later part of M4 adds
/// is `Unsupported`, named with that part.
fn query_at(
  q : @ast.Query,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  if q.with_ is [first, ..] {
    return unsupported("WITH (M4b2)", first.span)
  }
  // LIMIT and OFFSET see the outer scope, not the variables of this query.
  let limit = clause_at(q.limit, "LIMIT", scope, depth)
  let offset = clause_at(q.offset, "OFFSET", scope, depth)
  // The body, the output names a sort key may use, and the scope of the
  // sort keys.
  let (body, aliases, keys_scope) = match q.body {
    Select(s) => {
      let (body, aliases, inner) = select_parts(s, scope, depth)
      (body, aliases, inner.with_outputs(aliases))
    }
    Expr(e) =>
      (lower_at(e, scope, depth), [], scope.inner([@plan.row_variable]))
    SetOp(op) => return unsupported("a set operation (M4b2)", op.span)
    Table(_) => return unsupported("TABLE (later)", q.span)
  }
  if q.order_by.is_empty() && limit is None && offset is None {
    return body
  }
  let order = q.order_by.map(spec => {
    let desc = spec.order is Some(Desc)
    let nulls_first = match spec.nulls {
      Some(First) => true
      Some(Last) => false
      None => desc
    }
    @plan.SortKey::{
      expr: lower_at(spec.expr, keys_scope, depth),
      desc,
      nulls_first,
    }
  })
  Query(body, order~, limit~, offset~, aliases~, q.span)
}

///|
/// Whether `e` is an integer literal below 0: a minus sign on a literal.
fn negative_literal(e : @ast.Expr) -> Bool {
  match e.kind {
    Unary(Neg, { kind: Lit(Int(text)), .. }) =>
      text.iter().any(c => c >= '1' && c <= '9')
    _ => false
  }
}

///|
/// Lowers a LIMIT or OFFSET expression in `scope`. A negative literal is a
/// `DataError` in both modes (plan ruling 3).
fn clause_at(
  clause : @ast.Expr?,
  name : String,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr? raise @plan.EvalError {
  guard clause is Some(e) else { return None }
  if negative_literal(e) {
    raise DataError(message="\{name} must not be negative", span=e.span)
  }
  match e.kind {
    // A count beyond Int64 is valid (OFFSET skips all rows, LIMIT keeps
    // them all), so this literal is not range-checked.
    Lit(Int(text)) =>
      Some(
        Const(@value.Value::integer(@bigint.BigInt::from_string(text)), e.span),
      )
    _ => Some(lower_at(e, scope, depth))
  }
}

///|
/// Lowers a query block: the plan, the output names of its SELECT list (in
/// order, none for `SELECT VALUE` and `*`), and the scope inside it (its FROM
/// and LET variables).
fn select_parts(
  s : @ast.Select,
  scope : Scope,
  depth : Int32,
) -> (@plan.Expr, Array[String], Scope) raise @plan.EvalError {
  if s.group_by is Some(g) {
    return unsupported("GROUP BY (M4c)", g.span)
  }
  if s.having is Some(e) {
    return unsupported("HAVING (M4c)", e.span)
  }
  let names = []
  let sources = Ref(0)
  let from = match s.from {
    Some(item) => from_item(item, scope, names, sources, depth)
    None => return unsupported("SELECT without FROM (M4b1)", s.span)
  }
  let variables = from_variables(from)
  // A LET expression sees the variables before it, so `names` grows as the
  // bindings are lowered.
  let bindings = []
  for l in s.let_ {
    bindings.push((l.name.text, lower_at(l.expr, scope.inner(names), depth)))
    names.push(l.name.text)
  }
  let inner = scope.inner(names)
  let let_rel : @plan.Rel = if bindings.is_empty() {
    from
  } else {
    Let(from, bindings, s.let_[0].span)
  }
  let rel : @plan.Rel = match s.where_ {
    Some(w) => Filter(let_rel, lower_at(w, inner, depth), w.span)
    None => let_rel
  }
  let aliases = []
  let projection : @plan.Projection = match s.projection {
    Value(e) => Value(lower_at(e, inner, depth))
    Star(_) => Star(variables)
    Items(items) => {
      let out : Array[@plan.Item] = []
      for i, item in items {
        out.push(
          match item {
            Expr(e, as_~, ..) => {
              let name = match as_ {
                Some(id) => id.text
                None => implicit_name(e, i)
              }
              aliases.push(name)
              @plan.Item::Named(name, lower_at(e, inner, depth))
            }
            AllFields(e, ..) => @plan.Item::AllFields(lower_at(e, inner, depth))
          },
        )
      }
      Items(out)
    }
    Pivot(..) => return unsupported("PIVOT (M4b2)", s.span)
  }
  (
    Select(rel, projection, distinct=s.quantifier is Some(Distinct), s.span),
    aliases,
    inner,
  )
}

///|
/// The variable of a FROM source: its `AS` name, else the name of the
/// variable or of the last field of the path it scans, else `_` and its
/// position among the sources of the query block, from 1 (partiql-lang-kotlin's
/// rule; `SELECT * FROM <<{'a': 1}>>, <<{'b': 2}>>` needs two names).
fn from_name(source : @ast.FromSource, position : Int32) -> String {
  match source.as_ {
    Some(id) => id.text
    None => implicit_name(source.expr, position)
  }
}

///|
/// The name of an expression without `AS`: the name of the variable or of the
/// last field of the path, else `_` and the position `index` (from 0) in its
/// list plus 1.
fn implicit_name(e : @ast.Expr, index : Int32) -> String {
  match e.kind {
    VarRef(id, ..) => id.text
    Path(_, [.., Field(id)]) => id.text
    Path(_, [.., FieldString(name, ..)]) => name
    _ => "_\{index + 1}"
  }
}

///|
/// The variables that a FROM binds, without the `AT` ones, in FROM order. A
/// loop with a stack of pending relations, so a long chain of joins takes no
/// recursion.
fn from_variables(rel : @plan.Rel) -> Array[String] {
  let names = []
  let pending = [rel]
  while pending.pop() is Some(r) {
    match r {
      Scan(_, as_~, at=_, _) | Unpivot(_, as_~, at=_, _) => names.push(as_)
      Filter(input, _, _) | Let(input, _, _) => pending.push(input)
      Join(_, l, r, on=_, _) => {
        pending.push(r)
        pending.push(l)
      }
    }
  }
  names
}

///|
/// Lowers a FROM item and appends the variables it declares to `names`, in
/// order. A source sees the variables that come before it (lateral). A list
/// of sources is a chain of joins on the left: the loop walks that chain, so
/// a long list takes no recursion per item.
fn from_item(
  item : @ast.FromItem,
  scope : Scope,
  names : Array[String],
  sources : Ref[Int32],
  depth : Int32,
) -> @plan.Rel raise @plan.EvalError {
  if depth >= max_depth {
    raise DataError(
      message="FROM list is too deeply nested",
      span=from_span(item),
    )
  }
  let joins = []
  let mut leaf = item
  while leaf is Join(j) {
    joins.push(j)
    leaf = j.left
  }
  let mut rel = from_leaf(leaf, scope, names, sources, depth)
  for j in joins.rev_iter() {
    let kind : @plan.JoinKind = match (j.kind, j.form) {
      (Full, _) => return unsupported("FULL JOIN (later)", j.span)
      (Inner, Comma | Cross) => Cross
      (Inner, On(_)) => Inner
      (Left, _) => Left
      (Right, _) => Right
    }
    // The right side of a RIGHT JOIN is read once, outside the left rows.
    let right = if kind is Right {
      let own = []
      let right = from_item(j.right, scope, own, sources, depth + 1)
      for name in own {
        declare_variable(names, name, j.span)
      }
      right
    } else {
      from_item(j.right, scope, names, sources, depth + 1)
    }
    let on = match j.form {
      On(e) => Some(lower_at(e, scope.inner(names), depth))
      Comma | Cross => None
    }
    rel = Join(kind, rel, right, on~, j.span)
  }
  rel
}

///|
/// Declares the FROM variable `name` in `names`. A repeat of a name in one
/// FROM clause is an error, as in SQL. Declared names compare exactly: the
/// conformance suite keeps `an_alias` and `AN_ALIAS` apart as two variables
/// (a lookup by regular identifier finds both and is ambiguous).
fn declare_variable(
  names : Array[String],
  name : String,
  span : @ast.Span,
) -> Unit raise @plan.EvalError {
  if names.contains(name) {
    raise DataError(
      message="FROM variable \{name} is declared twice; name one of them with AS",
      span~,
    )
  }
  names.push(name)
}

///|
fn from_leaf(
  item : @ast.FromItem,
  scope : Scope,
  names : Array[String],
  sources : Ref[Int32],
  depth : Int32,
) -> @plan.Rel raise @plan.EvalError {
  let (source, unpivot) = match item {
    Scan(source) => (source, false)
    Unpivot(source) => (source, true)
    // `from_item` walks every join down to a source.
    Join(j) => return unsupported("a join in a source position", j.span)
  }
  if source.by is Some(id) {
    return unsupported("FROM ... BY (later)", id.span)
  }
  let as_ = from_name(source, sources.val)
  sources.val += 1
  let at = source.at.map(id => id.text)
  let expr = lower_plain(source.expr, scope.inner(names).for_source(), depth)
  if source.at is Some(id) {
    declare_variable(names, id.text, id.span)
  }
  declare_variable(names, as_, source.span)
  if unpivot {
    Unpivot(expr, as_~, at~, source.span)
  } else {
    Scan(expr, as_~, at~, source.span)
  }
}

///|
fn from_span(item : @ast.FromItem) -> @ast.Span {
  match item {
    Scan(s) | Unpivot(s) => s.span
    Join(j) => j.span
  }
}

///|
/// Whether `e` is a subquery `(SELECT item FROM ...)` with exactly one
/// projection item that is not `SELECT VALUE`, `*` or `x.*`.
fn is_single_column(e : @ast.Expr) -> Bool {
  match e.kind {
    Query({ body: Select({ projection: Items([Expr(_, ..)]), .. }), .. }) =>
      true
    _ => false
  }
}

///|
/// Lowers an expression where a FROM source, the collection of an `IN` or a
/// statement stands: a subquery there is not coerced.
fn lower_plain(
  e : @ast.Expr,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  match e.kind {
    Query(q) => {
      if depth >= max_depth {
        raise DataError(message="expression is too deep", span=e.span)
      }
      query_at(q, scope, depth + 1)
    }
    _ => lower_at(e, scope, depth)
  }
}

///|
/// Lowers the collection of an `IN`: a single-column `SELECT` there is the
/// bag of the value of each row.
fn column_at(
  e : @ast.Expr,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  let inner = lower_plain(e, scope, depth)
  if is_single_column(e) {
    Subquery(inner, Column, e.span)
  } else {
    inner
  }
}
