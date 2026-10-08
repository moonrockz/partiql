///|
/// The variables that FROM and LET declare, in the order they are declared,
/// with the scope of the enclosing query (spec M4b1 §4).
priv struct Scope {
  names : Array[String]
  outer : Scope?
  /// Inside a FROM source, a plain name finds a global before a variable.
  globals_first : Bool
}

///|
/// The scope outside every query: no variables.
fn Scope::top() -> Scope {
  { names: [], outer: None, globals_first: false, }
}

///|
/// A scope inside `self` that declares `names`.
fn Scope::inner(self : Scope, names : Array[String]) -> Scope {
  { names, outer: Some(self), globals_first: false, }
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
/// query in FROM order.
fn Scope::locals(self : Scope) -> Array[String] {
  let all = []
  let mut scope = Some(self)
  while scope is Some(s) {
    all.append(s.names)
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
  depth : Int,
) -> @plan.Expr raise @plan.EvalError {
  if q.with_ is [first, ..] {
    return unsupported("WITH (M4b2)", first.span)
  }
  if q.order_by is [first, ..] {
    return unsupported("ORDER BY (M4b2)", first.span)
  }
  if q.limit is Some(e) {
    return unsupported("LIMIT (M4b2)", e.span)
  }
  if q.offset is Some(e) {
    return unsupported("OFFSET (M4b2)", e.span)
  }
  match q.body {
    Expr(e) => lower_at(e, scope, depth)
    Select(s) => select_at(s, scope, depth)
    SetOp(op) => unsupported("a set operation (M4b2)", op.span)
    Table(_) => unsupported("TABLE (later)", q.span)
  }
}

///|
fn select_at(
  s : @ast.Select,
  scope : Scope,
  depth : Int,
) -> @plan.Expr raise @plan.EvalError {
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
  let projection : @plan.Projection = match s.projection {
    Value(e) => Value(lower_at(e, inner, depth))
    Star(_) => Star(variables)
    Items(items) => {
      let out : Array[@plan.Item] = []
      for i, item in items {
        out.push(
          match item {
            Expr(e, as_~, ..) =>
              @plan.Item::Named(
                match as_ {
                  Some(id) => id.text
                  None => implicit_name(e, i)
                },
                lower_at(e, inner, depth),
              )
            AllFields(e, ..) => @plan.Item::AllFields(lower_at(e, inner, depth))
          },
        )
      }
      Items(out)
    }
    Pivot(..) => return unsupported("PIVOT (M4b2)", s.span)
  }
  Select(rel, projection, distinct=s.quantifier is Some(Distinct), s.span)
}

///|
/// The variable of a FROM source: its `AS` name, else the name of the
/// variable or of the last field of the path it scans, else `_` and its
/// position among the sources of the query block, from 1 (partiql-lang-kotlin's
/// rule; `SELECT * FROM <<{'a': 1}>>, <<{'b': 2}>>` needs two names).
fn from_name(source : @ast.FromSource, position : Int) -> String {
  match source.as_ {
    Some(id) => id.text
    None => implicit_name(source.expr, position)
  }
}

///|
/// The name of an expression without `AS`: the name of the variable or of the
/// last field of the path, else `_` and the position `index` (from 0) in its
/// list plus 1.
fn implicit_name(e : @ast.Expr, index : Int) -> String {
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
  sources : Ref[Int],
  depth : Int,
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
      names.append(own)
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
fn from_leaf(
  item : @ast.FromItem,
  scope : Scope,
  names : Array[String],
  sources : Ref[Int],
  depth : Int,
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
  if at is Some(name) {
    names.push(name)
  }
  names.push(as_)
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
  depth : Int,
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
  depth : Int,
) -> @plan.Expr raise @plan.EvalError {
  let inner = lower_plain(e, scope, depth)
  if is_single_column(e) {
    Subquery(inner, Column, e.span)
  } else {
    inner
  }
}
