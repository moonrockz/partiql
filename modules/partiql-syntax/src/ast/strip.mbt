// strip_spans: the same tree with every span set to zero, so that the
// derived Eq compares structure only (spec M3a section 3).

///|
let no_span : Span = { start: 0, end: 0, }

///|
fn strip_ident(i : Identifier, fold : Bool) -> Identifier {
  {
    ..i,
    text: if fold && !i.delimited {
      i.text.to_lower()
    } else {
      i.text
    },
    span: no_span,
  }
}

///|
fn strip_ident_opt(i : Identifier?, fold : Bool) -> Identifier? {
  i.map(x => strip_ident(x, fold))
}

///|
fn strip_opt(e : Expr?, fold : Bool) -> Expr? {
  e.map(x => strip_expr(x, fold))
}

///|
fn strip_exprs(xs : Array[Expr], fold : Bool) -> Array[Expr] {
  xs.map(x => strip_expr(x, fold))
}

///|
fn strip_fields(fs : Array[(Expr, Expr)], fold : Bool) -> Array[(Expr, Expr)] {
  fs.map(f => (strip_expr(f.0, fold), strip_expr(f.1, fold)))
}

///|
fn strip_type(t : DataType, fold : Bool) -> DataType {
  match t {
    Map(k, v) => Map(strip_type(k, fold), strip_type(v, fold))
    Array(e) => Array(e.map(x => strip_type(x, fold)))
    Custom(i) => Custom(strip_ident(i, fold))
    other => other
  }
}

///|
fn strip_step(s : PathStep, fold : Bool) -> PathStep {
  match s {
    Field(i) => Field(strip_ident(i, fold))
    FieldString(t, ..) => FieldString(t, span=no_span)
    Index(e) => Index(strip_expr(e, fold))
    AllElements(_) => AllElements(no_span)
    AllFields(_) => AllFields(no_span)
  }
}

///|
fn strip_expr(e : Expr, fold : Bool) -> Expr {
  let kind : ExprKind = match e.kind {
    Lit(_) | Parameter | Error | CurrentDatetime(_, ..) => e.kind
    VarRef(i, qualified~) => VarRef(strip_ident(i, fold), qualified~)
    Path(b, steps) =>
      Path(strip_expr(b, fold), steps.map(x => strip_step(x, fold)))
    Unary(op, x) => Unary(op, strip_expr(x, fold))
    Binary(op, a, b) => Binary(op, strip_expr(a, fold), strip_expr(b, fold))
    And(a, b) => And(strip_expr(a, fold), strip_expr(b, fold))
    Or(a, b) => Or(strip_expr(a, fold), strip_expr(b, fold))
    Not(a) => Not(strip_expr(a, fold))
    BoolTest(x, v, negated~) => BoolTest(strip_expr(x, fold), v, negated~)
    Like(x, pattern~, escape~, negated~) =>
      Like(
        strip_expr(x, fold),
        pattern=strip_expr(pattern, fold),
        escape=strip_opt(escape, fold),
        negated~,
      )
    Between(x, low~, high~, negated~) =>
      Between(
        strip_expr(x, fold),
        low=strip_expr(low, fold),
        high=strip_expr(high, fold),
        negated~,
      )
    In(a, b, negated~) => In(strip_expr(a, fold), strip_expr(b, fold), negated~)
    IsNull(x, negated~) => IsNull(strip_expr(x, fold), negated~)
    IsMissing(x, negated~) => IsMissing(strip_expr(x, fold), negated~)
    IsType(x, t, negated~) =>
      IsType(strip_expr(x, fold), strip_type(t, fold), negated~)
    Overlaps(a, b) => Overlaps(strip_expr(a, fold), strip_expr(b, fold))
    Case(operand~, branches~, default~) =>
      Case(
        operand=strip_opt(operand, fold),
        branches=branches.map(b => {
          (strip_expr(b.0, fold), strip_expr(b.1, fold))
        }),
        default=strip_opt(default, fold),
      )
    Cast(x, t) => Cast(strip_expr(x, fold), strip_type(t, fold))
    Extract(f, x) => Extract(f, strip_expr(x, fold))
    Trim(spec~, chars~, x) =>
      Trim(spec~, chars=strip_opt(chars, fold), strip_expr(x, fold))
    Substring(x, start~, length~) =>
      Substring(
        strip_expr(x, fold),
        start=strip_expr(start, fold),
        length=strip_opt(length, fold),
      )
    Position(a, b) => Position(strip_expr(a, fold), strip_expr(b, fold))
    Overlay(x, placing~, from~, for_~) =>
      Overlay(
        strip_expr(x, fold),
        placing=strip_expr(placing, fold),
        from=strip_expr(from, fold),
        for_=strip_opt(for_, fold),
      )
    Coalesce(xs) => Coalesce(strip_exprs(xs, fold))
    NullIf(a, b) => NullIf(strip_expr(a, fold), strip_expr(b, fold))
    DateAdd(f, a, b) => DateAdd(f, strip_expr(a, fold), strip_expr(b, fold))
    DateDiff(f, a, b) => DateDiff(f, strip_expr(a, fold), strip_expr(b, fold))
    Call(i, args, quantifier~) =>
      Call(strip_ident(i, fold), strip_exprs(args, fold), quantifier~)
    CallStar(i) => CallStar(strip_ident(i, fold))
    List(xs) => List(strip_exprs(xs, fold))
    Bag(xs) => Bag(strip_exprs(xs, fold))
    Sexp(xs) => Sexp(strip_exprs(xs, fold))
    Struct(fs) => Struct(strip_fields(fs, fold))
    Map(fs) => Map(strip_fields(fs, fold))
    Row(xs) => Row(strip_exprs(xs, fold))
    Values(xs) => Values(strip_exprs(xs, fold))
    Query(q) => Query(strip_query(q, fold))
    GraphMatch(m) => GraphMatch(strip_match(m, fold))
  }
  { kind, span: no_span, }
}

///|
fn strip_query(q : Query, fold : Bool) -> Query {
  let body : QueryBody = match q.body {
    Select(s) => Select(strip_select(s, fold))
    SetOp(op) =>
      SetOp({
        ..op,
        corresponding: op.corresponding.map(c => {
          match c {
            By(names) => By(names.map(x => strip_ident(x, fold)))
            other => other
          }
        }),
        left: strip_query(op.left, fold),
        right: strip_query(op.right, fold),
        span: no_span,
      })
    Expr(e) => Expr(strip_expr(e, fold))
    Table(names) => Table(names.map(x => strip_ident(x, fold)))
  }
  {
    with_: q.with_.map(w => WithBinding::{
      name: strip_ident(w.name, fold),
      query: strip_query(w.query, fold),
      span: no_span,
    }),
    body,
    order_by: q.order_by.map(s => {
      ..s,
      expr: strip_expr(s.expr, fold),
      span: no_span,
    }),
    limit: strip_opt(q.limit, fold),
    offset: strip_opt(q.offset, fold),
    span: no_span,
  }
}

///|
fn strip_item(i : SelectItem, fold : Bool) -> SelectItem {
  match i {
    Expr(e, as_~, ..) =>
      Expr(strip_expr(e, fold), as_=strip_ident_opt(as_, fold), span=no_span)
    AllFields(e, ..) => AllFields(strip_expr(e, fold), span=no_span)
  }
}

///|
fn strip_select(s : Select, fold : Bool) -> Select {
  let projection : Projection = match s.projection {
    Star(_) => Star(no_span)
    Items(items) => Items(items.map(x => strip_item(x, fold)))
    Value(e) => Value(strip_expr(e, fold))
    Pivot(value~, key~) =>
      Pivot(value=strip_expr(value, fold), key=strip_expr(key, fold))
  }
  {
    ..s,
    projection,
    from: s.from.map(x => strip_from(x, fold)),
    let_: s.let_.map(l => LetBinding::{
      expr: strip_expr(l.expr, fold),
      name: strip_ident(l.name, fold),
      span: no_span,
    }),
    where_: strip_opt(s.where_, fold),
    group_by: s.group_by.map(x => strip_group(x, fold)),
    having: strip_opt(s.having, fold),
    span: no_span,
  }
}

///|
fn strip_group(g : GroupBy, fold : Bool) -> GroupBy {
  let keys : GroupKeys = match g.keys {
    By(ks, partial~) =>
      By(
        ks.map(k => GroupKey::{
          expr: strip_expr(k.expr, fold),
          as_: strip_ident_opt(k.as_, fold),
          span: no_span,
        }),
        partial~,
      )
    other => other
  }
  { keys, group_as: strip_ident_opt(g.group_as, fold), span: no_span, }
}

///|
fn strip_source(s : FromSource, fold : Bool) -> FromSource {
  {
    ..s,
    expr: strip_expr(s.expr, fold),
    as_: strip_ident_opt(s.as_, fold),
    at: strip_ident_opt(s.at, fold),
    by: strip_ident_opt(s.by, fold),
    span: no_span,
  }
}

///|
fn strip_from(f : FromItem, fold : Bool) -> FromItem {
  match f {
    Scan(s) => Scan(strip_source(s, fold))
    Unpivot(s) => Unpivot(strip_source(s, fold))
    Join(j) => {
      let form : JoinForm = match j.form {
        On(c) => On(strip_expr(c, fold))
        other => other
      }
      Join({
        ..j,
        form,
        left: strip_from(j.left, fold),
        right: strip_from(j.right, fold),
        span: no_span,
      })
    }
  }
}

///|
fn strip_label(l : Label, fold : Bool) -> Label {
  let kind : LabelKind = match l.kind {
    Name(i) => Name(strip_ident(i, fold))
    Wildcard => Wildcard
    Not(x) => Not(strip_label(x, fold))
    And(a, b) => And(strip_label(a, fold), strip_label(b, fold))
    Or(a, b) => Or(strip_label(a, fold), strip_label(b, fold))
  }
  { kind, span: no_span, }
}

///|
fn strip_quantifier(q : Quantifier?) -> Quantifier? {
  q.map(x => { ..x, span: no_span, })
}

///|
fn strip_path(p : PathPattern, fold : Bool) -> PathPattern {
  {
    ..p,
    variable: strip_ident_opt(p.variable, fold),
    parts: p.parts.map(x => strip_part(x, fold)),
    span: no_span,
  }
}

///|
fn strip_part(p : PathPart, fold : Bool) -> PathPart {
  match p {
    Node(n) =>
      Node(NodePattern::{
        variable: strip_ident_opt(n.variable, fold),
        label: n.label.map(x => strip_label(x, fold)),
        where_: strip_opt(n.where_, fold),
        span: no_span,
      })
    Edge(e) =>
      Edge({
        ..e,
        filler: e.filler.map(f => EdgeFiller::{
          variable: strip_ident_opt(f.variable, fold),
          label: f.label.map(x => strip_label(x, fold)),
          where_: strip_opt(f.where_, fold),
          span: no_span,
        }),
        quantifier: strip_quantifier(e.quantifier),
        span: no_span,
      })
    Group(g) =>
      Group({
        ..g,
        path: strip_path(g.path, fold),
        where_: strip_opt(g.where_, fold),
        quantifier: strip_quantifier(g.quantifier),
        span: no_span,
      })
  }
}

///|
fn strip_match(m : GraphMatch, fold : Bool) -> GraphMatch {
  {
    graph: strip_expr(m.graph, fold),
    pattern: GraphPattern::{
      selector: m.pattern.selector.map(s => { ..s, span: no_span, }),
      paths: m.pattern.paths.map(x => strip_path(x, fold)),
      where_: strip_opt(m.pattern.where_, fold),
      span: no_span,
    },
    span: no_span,
  }
}

///|
/// The same expression with every span set to `{ start: 0, end: 0 }`.
pub fn Expr::strip_spans(self : Expr) -> Expr {
  strip_expr(self, false)
}

///|
/// The same expression with every span zero and every regular identifier in
/// lower case: regular identifiers compare without case, so two expressions
/// with equal canonical forms mean the same thing (GROUP BY key matching,
/// spec M4c §3.5.2).
pub fn Expr::canonical(self : Expr) -> Expr {
  strip_expr(self, true)
}

///|
/// The same query with every span set to `{ start: 0, end: 0 }`.
pub fn Query::strip_spans(self : Query) -> Query {
  strip_query(self, false)
}

///|
/// The same statement with every span set to `{ start: 0, end: 0 }`, so that
/// `==` compares structure only.
pub fn Statement::strip_spans(self : Statement) -> Statement {
  match self {
    Query(q) => Query(strip_query(q, false))
    Error(_) => Error(no_span)
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
