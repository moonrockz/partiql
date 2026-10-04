// Test support: random syntax trees that the parser can produce (spec M3a
// section 10). print → parse must give each one back.

///|
let span0 : @ast.Span = { start: 0, end: 0, }

///|
fn mk(kind : @ast.ExprKind) -> @ast.Expr {
  { kind, span: span0, }
}

///|
fn name(text : String) -> @ast.Identifier {
  { text, delimited: false, span: span0, }
}

///|
fn quoted(text : String) -> @ast.Identifier {
  { text, delimited: true, span: span0, }
}

///|
fn pick(rs : @splitmix.RandomState, n : Int) -> Int {
  rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn chance(rs : @splitmix.RandomState, n : Int) -> Bool {
  pick(rs, n) == 0
}

///|
fn[T] one_of(rs : @splitmix.RandomState, xs : Array[T]) -> T {
  xs[pick(rs, xs.length())]
}

///|
/// Regular names that are not reserved; quoted names with awkward text.
fn gen_ident(rs : @splitmix.RandomState) -> @ast.Identifier {
  if chance(rs, 4) {
    quoted(one_of(rs, ["q", "all", "a\"b", "two words", "日本"]))
  } else {
    name(one_of(rs, ["a", "b", "x1", "Foo", "count", "year", "any", "trail"]))
  }
}

///|
fn gen_field_name(rs : @splitmix.RandomState) -> @ast.Identifier {
  if chance(rs, 5) {
    quoted("F")
  } else {
    name(one_of(rs, ["a", "b", "date", "timestamp", "year"]))
  }
}

///|
fn gen_literal(rs : @splitmix.RandomState) -> @ast.Literal raise {
  match pick(rs, 13) {
    0 => Int(one_of(rs, ["0", "42"]))
    1 => Decimal(one_of(rs, ["1.5", "0.25"]))
    2 => Float(one_of(rs, ["3e2", "1.5E-3"]))
    3 => String(one_of(rs, ["s", "it's", "", "héllo"]))
    4 => Bool(chance(rs, 2))
    5 => Null
    6 => Missing
    7 => Date("2021-01-01")
    8 =>
      Time(
        "12:00:00",
        precision=if chance(rs, 2) { Some(3) } else { None },
        with_tz=chance(rs, 2),
      )
    9 => Timestamp("2021-01-01 12:00:00", precision=None, with_tz=chance(rs, 2))
    10 =>
      Interval("1-2", negative=chance(rs, 2), qualifier={
        start: Year,
        start_precision: None,
        end: Some(Month),
        fractional_precision: None,
      })
    11 =>
      Interval("5", negative=false, qualifier={
        start: Second,
        start_precision: Some(2),
        end: None,
        fractional_precision: Some(3),
      })
    _ => {
      let text = one_of(rs, ["1", "{a: 1}", "[1, \"x\"]"])
      Ion(text, @text.read_ion(text))
    }
  }
}

///|
fn gen_type(rs : @splitmix.RandomState, depth : Int) -> @ast.DataType {
  match pick(rs, if depth > 0 { 12 } else { 10 }) {
    0 => Int
    1 => Decimal(Some(5), Some(2))
    2 => Decimal(Some(5), None)
    3 => Varchar(Some(3))
    4 => Double(None)
    5 => Double(Some(10))
    6 => Time(Some(3), with_tz=true)
    7 => Timestamp(None, with_tz=false)
    8 => Custom(if chance(rs, 2) { name("point") } else { quoted("Point") })
    9 => String
    10 => Map(gen_type(rs, depth - 1), gen_type(rs, depth - 1))
    _ => Array(if chance(rs, 2) { Some(gen_type(rs, depth - 1)) } else { None })
  }
}

///|
fn gen_atom(rs : @splitmix.RandomState) -> @ast.Expr raise {
  match pick(rs, 4) {
    0 => mk(VarRef(gen_ident(rs), qualified=chance(rs, 5)))
    1 => mk(Parameter)
    _ => mk(Lit(gen_literal(rs)))
  }
}

///|
fn gen_list(
  rs : @splitmix.RandomState,
  depth : Int,
  min : Int,
  max : Int,
) -> Array[@ast.Expr] raise {
  let out : Array[@ast.Expr] = []
  for _ in 0..<(min + pick(rs, max - min + 1)) {
    out.push(gen_expr(rs, depth - 1))
  }
  out
}

///|
let binary_ops : Array[@ast.BinaryOp] = [
  Add,
  Sub,
  Mul,
  Div,
  Mod,
  Concat,
  Eq,
  Ne,
  Lt,
  Le,
  Gt,
  Ge,
]

///|
let fields : Array[@ast.DatetimeField] = [
  Year,
  Month,
  Day,
  Hour,
  Minute,
  Second,
]

///|
/// The right side of IN: a row, a subquery, a name or a list (an expression
/// that prints starting with `(` and is not a row cannot be written there).
fn gen_in_rhs(rs : @splitmix.RandomState, depth : Int) -> @ast.Expr raise {
  match pick(rs, 4) {
    0 => mk(Row(gen_list(rs, depth, 1, 3)))
    1 => mk(Query(gen_query(rs, depth - 1)))
    2 => mk(VarRef(gen_ident(rs), qualified=false))
    _ => mk(List(gen_list(rs, depth, 0, 2)))
  }
}

///|
fn gen_steps(
  rs : @splitmix.RandomState,
  depth : Int,
) -> Array[@ast.PathStep] raise {
  let out : Array[@ast.PathStep] = []
  for _ in 0..<(1 + pick(rs, 3)) {
    out.push(
      match pick(rs, 5) {
        0 => Field(gen_field_name(rs))
        1 => FieldString(one_of(rs, ["k", "it's"]), span=span0)
        2 => Index(gen_expr(rs, depth - 1))
        3 => AllElements(span0)
        _ => AllFields(span0)
      },
    )
  }
  out
}

///|
fn gen_expr(rs : @splitmix.RandomState, depth : Int) -> @ast.Expr raise {
  if depth <= 0 {
    return gen_atom(rs)
  }
  let d = depth - 1
  match pick(rs, 34) {
    0 => gen_atom(rs)
    1 => mk(Unary(if chance(rs, 2) { Neg } else { Pos }, gen_expr(rs, d)))
    2 | 3 | 4 =>
      mk(Binary(one_of(rs, binary_ops), gen_expr(rs, d), gen_expr(rs, d)))
    5 => mk(And(gen_expr(rs, d), gen_expr(rs, d)))
    6 => mk(Or(gen_expr(rs, d), gen_expr(rs, d)))
    7 => mk(Not(gen_expr(rs, d)))
    8 =>
      mk(
        BoolTest(
          gen_expr(rs, d),
          one_of(rs, [Some(true), Some(false), None]),
          negated=chance(rs, 2),
        ),
      )
    9 =>
      mk(
        Like(
          gen_expr(rs, d),
          pattern=gen_expr(rs, d),
          escape=if chance(rs, 2) { Some(gen_expr(rs, d)) } else { None },
          negated=chance(rs, 2),
        ),
      )
    10 =>
      mk(
        Between(
          gen_expr(rs, d),
          low=gen_expr(rs, d),
          high=gen_expr(rs, d),
          negated=chance(rs, 2),
        ),
      )
    11 => mk(In(gen_expr(rs, d), gen_in_rhs(rs, depth), negated=chance(rs, 2)))
    12 => mk(IsNull(gen_expr(rs, d), negated=chance(rs, 2)))
    13 => mk(IsMissing(gen_expr(rs, d), negated=chance(rs, 2)))
    14 => mk(IsType(gen_expr(rs, d), gen_type(rs, 2), negated=chance(rs, 2)))
    15 => mk(Overlaps(gen_expr(rs, d), gen_expr(rs, d)))
    16 => {
      let branches : Array[(@ast.Expr, @ast.Expr)] = []
      for _ in 0..<(1 + pick(rs, 2)) {
        branches.push((gen_expr(rs, d), gen_expr(rs, d)))
      }
      mk(
        Case(
          operand=if chance(rs, 2) { Some(gen_expr(rs, d)) } else { None },
          branches~,
          default=if chance(rs, 2) { Some(gen_expr(rs, d)) } else { None },
        ),
      )
    }
    17 => mk(Cast(gen_expr(rs, d), gen_type(rs, 2)))
    18 => mk(Extract(one_of(rs, fields), gen_expr(rs, d)))
    19 => {
      let spec : @ast.TrimSpec? = one_of(rs, [
        None,
        Some(Both),
        Some(Leading),
        Some(Trailing),
      ])
      mk(
        Trim(
          spec~,
          chars=if chance(rs, 2) { Some(gen_expr(rs, d)) } else { None },
          gen_expr(rs, d),
        ),
      )
    }
    20 =>
      mk(
        Substring(
          gen_expr(rs, d),
          start=gen_expr(rs, d),
          length=if chance(rs, 2) { Some(gen_expr(rs, d)) } else { None },
        ),
      )
    21 => mk(Position(gen_expr(rs, d), gen_expr(rs, d)))
    22 =>
      mk(
        Overlay(
          gen_expr(rs, d),
          placing=gen_expr(rs, d),
          from=gen_expr(rs, d),
          for_=if chance(rs, 2) { Some(gen_expr(rs, d)) } else { None },
        ),
      )
    23 => mk(Coalesce(gen_list(rs, depth, 1, 3)))
    24 => mk(NullIf(gen_expr(rs, d), gen_expr(rs, d)))
    25 => mk(DateAdd(one_of(rs, fields), gen_expr(rs, d), gen_expr(rs, d)))
    26 => {
      let args = gen_list(rs, depth, 0, 3)
      let quantifier : @ast.SetQuantifier? = if args.is_empty() {
        None
      } else {
        one_of(rs, [None, Some(Distinct), Some(All)])
      }
      mk(Call(name(one_of(rs, ["f", "upper_x"])), args, quantifier~))
    }
    27 => mk(CallStar(name("count")))
    28 => {
      let xs = gen_list(rs, depth, 0, 3)
      mk(
        match pick(rs, 4) {
          0 => List(xs)
          1 => Bag(xs)
          2 => Sexp(xs)
          _ => Row(xs)
        },
      )
    }
    29 => {
      let fs : Array[(@ast.Expr, @ast.Expr)] = []
      for _ in 0..<pick(rs, 3) {
        fs.push((gen_expr(rs, d), gen_expr(rs, d)))
      }
      mk(if chance(rs, 2) { Struct(fs) } else { Map(fs) })
    }
    30 | 31 => {
      // The parser gathers all steps into one path.
      let base = gen_expr(rs, d)
      let steps = gen_steps(rs, depth)
      match base.kind {
        Path(b, first) => mk(Path(b, first + steps))
        _ => mk(Path(base, steps))
      }
    }
    32 => mk(Query(gen_query(rs, d)))
    _ => {
      let rows : Array[@ast.Expr] = []
      for _ in 0..<(1 + pick(rs, 2)) {
        rows.push(mk(Row(gen_list(rs, depth, 1, 2))))
      }
      mk(Values(rows))
    }
  }
}

///|
/// A select item; a path ending in `.*` would read back as an `e.*` item.
fn gen_item(rs : @splitmix.RandomState, depth : Int) -> @ast.SelectItem raise {
  let e = gen_expr(rs, depth)
  let ends_all = e.kind is Path(_, steps) && steps.last() is Some(AllFields(_))
  if chance(rs, 5) {
    AllFields(mk(VarRef(gen_ident(rs), qualified=false)), span=span0)
  } else if ends_all {
    Expr(mk(VarRef(gen_ident(rs), qualified=false)), as_=None, span=span0)
  } else {
    Expr(
      e,
      as_=if chance(rs, 2) { Some(gen_ident(rs)) } else { None },
      span=span0,
    )
  }
}

///|
fn gen_source(rs : @splitmix.RandomState, depth : Int) -> @ast.FromItem raise {
  // Rows print as ROW(..) in FROM; other sources avoid a leading `(`,
  // which would start a parenthesized-join attempt.
  let expr = match pick(rs, 4) {
    0 => mk(Query(gen_query(rs, depth - 1)))
    3 => mk(Row(gen_list(rs, depth, 0, 3)))
    1 =>
      mk(
        Path(mk(VarRef(gen_ident(rs), qualified=false)), [
          Field(gen_field_name(rs)),
        ]),
      )
    _ => mk(VarRef(gen_ident(rs), qualified=false))
  }
  let source : @ast.FromSource = {
    lateral: chance(rs, 6),
    expr,
    as_: if chance(rs, 2) {
      Some(gen_ident(rs))
    } else {
      None
    },
    at: if chance(rs, 4) {
      Some(gen_ident(rs))
    } else {
      None
    },
    by: if chance(rs, 6) {
      Some(gen_ident(rs))
    } else {
      None
    },
    span: span0,
  }
  if chance(rs, 6) {
    Unpivot(source)
  } else {
    Scan(source)
  }
}

///|
fn gen_from(rs : @splitmix.RandomState, depth : Int) -> @ast.FromItem raise {
  if depth <= 0 || chance(rs, 2) {
    return gen_source(rs, depth)
  }
  let kind : @ast.JoinKind = one_of(rs, [Inner, Left, Right, Full])
  let form : @ast.JoinForm = match pick(rs, 3) {
    0 => Comma
    1 => Cross
    _ => On(gen_expr(rs, depth - 1))
  }
  Join({
    kind: if form is Comma {
      Inner
    } else {
      kind
    },
    form,
    left: gen_from(rs, depth - 1),
    right: gen_from(rs, depth - 1),
    span: span0,
  })
}

///|
fn gen_select(rs : @splitmix.RandomState, depth : Int) -> @ast.Select raise {
  let d = depth - 1
  let from = if chance(rs, 4) { None } else { Some(gen_from(rs, 2)) }
  let projection : @ast.Projection = match pick(rs, 5) {
    0 => Star(span0)
    1 => Value(gen_expr(rs, d))
    2 if from is Some(_) => Pivot(value=gen_expr(rs, d), key=gen_expr(rs, d))
    _ => {
      let items : Array[@ast.SelectItem] = []
      for _ in 0..<(1 + pick(rs, 2)) {
        items.push(gen_item(rs, d))
      }
      Items(items)
    }
  }
  let let_ : Array[@ast.LetBinding] = if chance(rs, 4) {
    [{ expr: gen_expr(rs, d), name: gen_ident(rs), span: span0, }]
  } else {
    []
  }
  let group_by : @ast.GroupBy? = match pick(rs, 5) {
    0 =>
      Some({
        keys: All,
        group_as: if chance(rs, 2) {
          Some(gen_ident(rs))
        } else {
          None
        },
        span: span0,
      })
    1 =>
      Some({
        keys: By(
          [
            {
              expr: gen_expr(rs, d),
              as_: if chance(rs, 2) {
                Some(gen_ident(rs))
              } else {
                None
              },
              span: span0,
            },
          ],
          partial=chance(rs, 3),
        ),
        group_as: if chance(rs, 2) {
          Some(gen_ident(rs))
        } else {
          None
        },
        span: span0,
      })
    _ => None
  }
  {
    quantifier: if projection is Pivot(..) {
      None
    } else {
      one_of(rs, [None, Some(Distinct), Some(All)])
    },
    projection,
    from,
    let_,
    where_: if chance(rs, 2) {
      Some(gen_expr(rs, d))
    } else {
      None
    },
    group_by,
    having: if group_by is Some(_) && chance(rs, 2) {
      Some(gen_expr(rs, d))
    } else {
      None
    },
    span: span0,
  }
}

///|
fn simple_query(body : @ast.QueryBody) -> @ast.Query {
  { with_: [], body, order_by: [], limit: None, offset: None, span: span0, }
}

///|
/// A query whose body is a SELECT, a set operation of SELECTs, or TABLE
/// (an expression body would print as a bare expression in subqueries).
fn gen_query(rs : @splitmix.RandomState, depth : Int) -> @ast.Query raise {
  let d = if depth > 0 { depth - 1 } else { 0 }
  let body : @ast.QueryBody = match pick(rs, 5) {
    0 =>
      Table(
        [gen_ident(rs)] + (if chance(rs, 2) { [gen_ident(rs)] } else { [] }),
      )
    1 =>
      SetOp({
        op: one_of(rs, [Union, Intersect, Except]),
        quantifier: one_of(rs, [None, Some(All), Some(Distinct)]),
        outer: chance(rs, 4),
        corresponding: one_of(rs, [None, Some(All), Some(By([gen_ident(rs)]))]),
        left: gen_query(rs, d),
        right: gen_query(rs, d),
        span: span0,
      })
    _ => Select(gen_select(rs, depth))
  }
  {
    with_: if chance(rs, 6) {
      [
        {
          name: gen_ident(rs),
          query: simple_query(Select(gen_select(rs, d))),
          span: span0,
        },
      ]
    } else {
      []
    },
    body,
    order_by: if chance(rs, 4) {
      [
        {
          expr: gen_expr(rs, d),
          order: one_of(rs, [None, Some(Asc), Some(Desc)]),
          nulls: one_of(rs, [None, Some(First), Some(Last)]),
          span: span0,
        },
      ]
    } else {
      []
    },
    limit: if chance(rs, 4) {
      Some(gen_expr(rs, d))
    } else {
      None
    },
    offset: if chance(rs, 6) {
      Some(gen_expr(rs, d))
    } else {
      None
    },
    span: span0,
  }
}

///|
/// A random statement.
struct TreeSpec {
  statement : @ast.Statement
} derive(Debug)

///|
impl @quickcheck.Arbitrary for TreeSpec with fn arbitrary(size, rs) {
  let depth = if size < 20 { 2 } else { 3 }
  let q = gen_query(rs, depth) catch { _ => simple_query(Table([name("t")])) }
  { statement: Query(q), }
}

///|
impl @quickcheck.Shrink for TreeSpec

///|
/// A random expression statement (`SELECT VALUE e`).
struct ExprSpec {
  expr : @ast.Expr
} derive(Debug)

///|
impl @quickcheck.Arbitrary for ExprSpec with fn arbitrary(size, rs) {
  let depth = if size < 20 { 3 } else { 4 }
  let expr = gen_expr(rs, depth) catch { _ => mk(Parameter) }
  { expr, }
}

///|
impl @quickcheck.Shrink for ExprSpec
