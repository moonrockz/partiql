// strip_spans: the same tree with every span set to zero, so that the
// derived Eq compares structure only (spec M3a section 3).

///|
let no_span : Span = { start: 0, end: 0, }

///|
fn strip_ident(i : Identifier) -> Identifier {
  { ..i, span: no_span, }
}

///|
fn strip_ident_opt(i : Identifier?) -> Identifier? {
  i.map(strip_ident)
}

///|
fn strip_opt(e : Expr?) -> Expr? {
  e.map(strip_expr)
}

///|
fn strip_exprs(xs : Array[Expr]) -> Array[Expr] {
  xs.map(strip_expr)
}

///|
fn strip_fields(fs : Array[(Expr, Expr)]) -> Array[(Expr, Expr)] {
  fs.map(f => (strip_expr(f.0), strip_expr(f.1)))
}

///|
fn strip_type(t : DataType) -> DataType {
  match t {
    Map(k, v) => Map(strip_type(k), strip_type(v))
    Array(e) => Array(e.map(strip_type))
    Custom(i) => Custom(strip_ident(i))
    other => other
  }
}

///|
fn strip_step(s : PathStep) -> PathStep {
  match s {
    Field(i) => Field(strip_ident(i))
    FieldString(t, ..) => FieldString(t, span=no_span)
    Index(e) => Index(strip_expr(e))
    AllElements(_) => AllElements(no_span)
    AllFields(_) => AllFields(no_span)
  }
}

///|
fn strip_expr(e : Expr) -> Expr {
  let kind : ExprKind = match e.kind {
    Lit(_) | Parameter => e.kind
    VarRef(i, qualified~) => VarRef(strip_ident(i), qualified~)
    Path(b, steps) => Path(strip_expr(b), steps.map(strip_step))
    Unary(op, x) => Unary(op, strip_expr(x))
    Binary(op, a, b) => Binary(op, strip_expr(a), strip_expr(b))
    And(a, b) => And(strip_expr(a), strip_expr(b))
    Or(a, b) => Or(strip_expr(a), strip_expr(b))
    Not(a) => Not(strip_expr(a))
    BoolTest(x, v, negated~) => BoolTest(strip_expr(x), v, negated~)
    Like(x, pattern~, escape~, negated~) =>
      Like(
        strip_expr(x),
        pattern=strip_expr(pattern),
        escape=strip_opt(escape),
        negated~,
      )
    Between(x, low~, high~, negated~) =>
      Between(
        strip_expr(x),
        low=strip_expr(low),
        high=strip_expr(high),
        negated~,
      )
    In(a, b, negated~) => In(strip_expr(a), strip_expr(b), negated~)
    IsNull(x, negated~) => IsNull(strip_expr(x), negated~)
    IsMissing(x, negated~) => IsMissing(strip_expr(x), negated~)
    IsType(x, t, negated~) => IsType(strip_expr(x), strip_type(t), negated~)
    Overlaps(a, b) => Overlaps(strip_expr(a), strip_expr(b))
    Case(operand~, branches~, default~) =>
      Case(
        operand=strip_opt(operand),
        branches=branches.map(b => (strip_expr(b.0), strip_expr(b.1))),
        default=strip_opt(default),
      )
    Cast(x, t) => Cast(strip_expr(x), strip_type(t))
    Extract(f, x) => Extract(f, strip_expr(x))
    Trim(spec~, chars~, x) => Trim(spec~, chars=strip_opt(chars), strip_expr(x))
    Substring(x, start~, length~) =>
      Substring(
        strip_expr(x),
        start=strip_expr(start),
        length=strip_opt(length),
      )
    Position(a, b) => Position(strip_expr(a), strip_expr(b))
    Overlay(x, placing~, from~, for_~) =>
      Overlay(
        strip_expr(x),
        placing=strip_expr(placing),
        from=strip_expr(from),
        for_=strip_opt(for_),
      )
    Coalesce(xs) => Coalesce(strip_exprs(xs))
    NullIf(a, b) => NullIf(strip_expr(a), strip_expr(b))
    DateAdd(f, a, b) => DateAdd(f, strip_expr(a), strip_expr(b))
    DateDiff(f, a, b) => DateDiff(f, strip_expr(a), strip_expr(b))
    Call(i, args, quantifier~) =>
      Call(strip_ident(i), strip_exprs(args), quantifier~)
    CallStar(i) => CallStar(strip_ident(i))
    List(xs) => List(strip_exprs(xs))
    Bag(xs) => Bag(strip_exprs(xs))
    Sexp(xs) => Sexp(strip_exprs(xs))
    Struct(fs) => Struct(strip_fields(fs))
    Map(fs) => Map(strip_fields(fs))
    Row(xs) => Row(strip_exprs(xs))
    Values(xs) => Values(strip_exprs(xs))
    Query(q) => Query(strip_query(q))
    GraphMatch(m) => GraphMatch(strip_match(m))
  }
  { kind, span: no_span, }
}

///|
fn strip_query(q : Query) -> Query {
  let body : QueryBody = match q.body {
    Select(s) => Select(strip_select(s))
    SetOp(op) =>
      SetOp({
        ..op,
        corresponding: op.corresponding.map(c => {
          match c {
            By(names) => By(names.map(strip_ident))
            other => other
          }
        }),
        left: strip_query(op.left),
        right: strip_query(op.right),
        span: no_span,
      })
    Expr(e) => Expr(strip_expr(e))
    Table(names) => Table(names.map(strip_ident))
  }
  {
    with_: q.with_.map(w => WithBinding::{
      name: strip_ident(w.name),
      query: strip_query(w.query),
      span: no_span,
    }),
    body,
    order_by: q.order_by.map(s => {
      ..s,
      expr: strip_expr(s.expr),
      span: no_span,
    }),
    limit: strip_opt(q.limit),
    offset: strip_opt(q.offset),
    span: no_span,
  }
}

///|
fn strip_item(i : SelectItem) -> SelectItem {
  match i {
    Expr(e, as_~, ..) =>
      Expr(strip_expr(e), as_=strip_ident_opt(as_), span=no_span)
    AllFields(e, ..) => AllFields(strip_expr(e), span=no_span)
  }
}

///|
fn strip_select(s : Select) -> Select {
  let projection : Projection = match s.projection {
    Star(_) => Star(no_span)
    Items(items) => Items(items.map(strip_item))
    Value(e) => Value(strip_expr(e))
    Pivot(value~, key~) => Pivot(value=strip_expr(value), key=strip_expr(key))
  }
  {
    ..s,
    projection,
    from: s.from.map(strip_from),
    let_: s.let_.map(l => LetBinding::{
      expr: strip_expr(l.expr),
      name: strip_ident(l.name),
      span: no_span,
    }),
    where_: strip_opt(s.where_),
    group_by: s.group_by.map(strip_group),
    having: strip_opt(s.having),
    span: no_span,
  }
}

///|
fn strip_group(g : GroupBy) -> GroupBy {
  let keys : GroupKeys = match g.keys {
    By(ks, partial~) =>
      By(
        ks.map(k => GroupKey::{
          expr: strip_expr(k.expr),
          as_: strip_ident_opt(k.as_),
          span: no_span,
        }),
        partial~,
      )
    other => other
  }
  { keys, group_as: strip_ident_opt(g.group_as), span: no_span, }
}

///|
fn strip_source(s : FromSource) -> FromSource {
  {
    ..s,
    expr: strip_expr(s.expr),
    as_: strip_ident_opt(s.as_),
    at: strip_ident_opt(s.at),
    by: strip_ident_opt(s.by),
    span: no_span,
  }
}

///|
fn strip_from(f : FromItem) -> FromItem {
  match f {
    Scan(s) => Scan(strip_source(s))
    Unpivot(s) => Unpivot(strip_source(s))
    Join(j) => {
      let form : JoinForm = match j.form {
        On(c) => On(strip_expr(c))
        other => other
      }
      Join({
        ..j,
        form,
        left: strip_from(j.left),
        right: strip_from(j.right),
        span: no_span,
      })
    }
  }
}

///|
fn strip_label(l : Label) -> Label {
  let kind : LabelKind = match l.kind {
    Name(i) => Name(strip_ident(i))
    Wildcard => Wildcard
    Not(x) => Not(strip_label(x))
    And(a, b) => And(strip_label(a), strip_label(b))
    Or(a, b) => Or(strip_label(a), strip_label(b))
  }
  { kind, span: no_span, }
}

///|
fn strip_quantifier(q : Quantifier?) -> Quantifier? {
  q.map(x => { ..x, span: no_span, })
}

///|
fn strip_path(p : PathPattern) -> PathPattern {
  {
    ..p,
    variable: strip_ident_opt(p.variable),
    parts: p.parts.map(strip_part),
    span: no_span,
  }
}

///|
fn strip_part(p : PathPart) -> PathPart {
  match p {
    Node(n) =>
      Node(NodePattern::{
        variable: strip_ident_opt(n.variable),
        label: n.label.map(strip_label),
        where_: strip_opt(n.where_),
        span: no_span,
      })
    Edge(e) =>
      Edge({
        ..e,
        filler: e.filler.map(f => EdgeFiller::{
          variable: strip_ident_opt(f.variable),
          label: f.label.map(strip_label),
          where_: strip_opt(f.where_),
          span: no_span,
        }),
        quantifier: strip_quantifier(e.quantifier),
        span: no_span,
      })
    Group(g) =>
      Group({
        ..g,
        path: strip_path(g.path),
        where_: strip_opt(g.where_),
        quantifier: strip_quantifier(g.quantifier),
        span: no_span,
      })
  }
}

///|
fn strip_match(m : GraphMatch) -> GraphMatch {
  {
    graph: strip_expr(m.graph),
    pattern: GraphPattern::{
      selector: m.pattern.selector.map(s => { ..s, span: no_span, }),
      paths: m.pattern.paths.map(strip_path),
      where_: strip_opt(m.pattern.where_),
      span: no_span,
    },
    span: no_span,
  }
}

///|
/// The same expression with every span set to `{ start: 0, end: 0 }`.
pub fn Expr::strip_spans(self : Expr) -> Expr {
  strip_expr(self)
}

///|
/// The same query with every span set to `{ start: 0, end: 0 }`.
pub fn Query::strip_spans(self : Query) -> Query {
  strip_query(self)
}

///|
/// The same statement with every span set to `{ start: 0, end: 0 }`, so that
/// `==` compares structure only.
pub fn Statement::strip_spans(self : Statement) -> Statement {
  match self {
    Query(q) => Query(strip_query(q))
  }
}

///|
/// The same script with every span set to `{ start: 0, end: 0 }`.
pub fn Script::strip_spans(self : Script) -> Script {
  {
    statements: self.statements.map(s => s.strip_spans()),
    comments: self.comments.map(c => { ..c, span: no_span, }),
    span: no_span,
  }
}
