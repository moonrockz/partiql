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
/// Lowers a query statement.
pub fn lower_query(q : @ast.Query) -> @plan.Expr raise @plan.EvalError {
  query_at(q, Scope::top(), 0)
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
  if s.let_ is [first, ..] {
    return unsupported("LET (M4b1)", first.span)
  }
  let names = []
  let from = match s.from {
    Some(item) => from_item(item, scope, names, depth)
    None => return unsupported("SELECT without FROM (M4b1)", s.span)
  }
  let inner = scope.inner(names)
  let rel : @plan.Rel = match s.where_ {
    Some(w) => Filter(from, lower_at(w, inner, depth), w.span)
    None => from
  }
  let projection : @plan.Projection = match s.projection {
    Value(e) => Value(lower_at(e, inner, depth))
    Star(span) => return unsupported("SELECT * (M4b1)", span)
    Items(_) => return unsupported("a SELECT list (M4b1)", s.span)
    Pivot(..) => return unsupported("PIVOT (M4b2)", s.span)
  }
  Select(rel, projection, distinct=s.quantifier is Some(Distinct), s.span)
}

///|
/// The variable of a FROM source: its `AS` name, else the name of the
/// variable or of the last field of the path it scans, else `_1`
/// (partiql-lang-kotlin's rule).
fn from_name(source : @ast.FromSource) -> String {
  match source.as_ {
    Some(id) => id.text
    None =>
      match source.expr.kind {
        VarRef(id, ..) => id.text
        Path(_, [.., Field(id)]) => id.text
        Path(_, [.., FieldString(name, ..)]) => name
        _ => "_1"
      }
  }
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
  // Each RIGHT JOIN in a chain wraps the rows before it when they run, so
  // every right side of the chain runs inside all of them. The guard counts
  // them all, which bounds the nesting along any path.
  let mut rights = 0
  for j in joins {
    if j.kind is Right {
      rights += 1
    }
  }
  if depth + rights >= max_depth {
    raise DataError(
      message="FROM list is too deeply nested",
      span=from_span(item),
    )
  }
  let mut rel = from_leaf(leaf, scope, names, depth)
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
      let right = from_item(j.right, scope, own, depth + rights + 1)
      names.append(own)
      right
    } else {
      from_item(j.right, scope, names, depth + rights + 1)
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
  let as_ = from_name(source)
  let at = source.at.map(id => id.text)
  let expr = lower_at(source.expr, scope.inner(names).for_source(), depth)
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
