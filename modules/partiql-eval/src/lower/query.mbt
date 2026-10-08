///|
/// The variables that FROM and LET declare, in the order they are declared,
/// with the scope of the enclosing query (spec M4b1 §4).
priv struct Scope {
  names : Array[String]
  outer : Scope?
}

///|
/// The scope outside every query: no variables.
fn Scope::top() -> Scope {
  { names: [], outer: None, }
}

///|
/// A scope inside `self` that declares `names`.
fn Scope::inner(self : Scope, names : Array[String]) -> Scope {
  { names, outer: Some(self), }
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
  let source = match s.from {
    Some(Scan(source)) => source
    Some(Unpivot(source)) => return unsupported("UNPIVOT (M4b1)", source.span)
    Some(Join(j)) => return unsupported("a join (M4b1)", j.span)
    None => return unsupported("SELECT without FROM (M4b1)", s.span)
  }
  if source.by is Some(id) {
    return unsupported("FROM ... BY (later)", id.span)
  }
  let as_ = from_name(source)
  let at = source.at.map(id => id.text)
  let names = match at {
    Some(name) => [name, as_]
    None => [as_]
  }
  let inner = scope.inner(names)
  let scan : @plan.Rel = Scan(
    lower_at(source.expr, scope, depth),
    as_~,
    at~,
    source.span,
  )
  let rel : @plan.Rel = match s.where_ {
    Some(w) => Filter(scan, lower_at(w, inner, depth), w.span)
    None => scan
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
