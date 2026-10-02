///|
fn within(inner : @ast.Span, outer : @ast.Span) -> Bool {
  outer.start <= inner.start && inner.end <= outer.end
}

///|
/// Each span is inside `outer`, and the spans are in order without overlap.
fn ordered_within(spans : Array[@ast.Span], outer : @ast.Span) -> Bool {
  for i, s in spans {
    if !within(s, outer) || (i > 0 && spans[i - 1].end > s.start) {
      return false
    }
  }
  true
}

///|
fn label_spans_ok(l : @ast.Label) -> Bool {
  match l.kind {
    Name(i) => within(i.span, l.span)
    Wildcard => true
    Not(x) => within(x.span, l.span) && label_spans_ok(x)
    And(a, b) | Or(a, b) =>
      ordered_within([a.span, b.span], l.span) &&
      label_spans_ok(a) &&
      label_spans_ok(b)
  }
}

///|
fn element_spans_ok(
  variable : @ast.Identifier?,
  label : @ast.Label?,
  where_ : @ast.Expr?,
  outer : @ast.Span,
) -> Bool {
  let spans : Array[@ast.Span] = []
  if variable is Some(v) {
    spans.push(v.span)
  }
  if label is Some(l) {
    spans.push(l.span)
  }
  if where_ is Some(w) {
    spans.push(w.span)
  }
  ordered_within(spans, outer) &&
  (match label {
    Some(l) => label_spans_ok(l)
    None => true
  })
}

///|
fn quantifier_inside(q : @ast.Quantifier?, outer : @ast.Span) -> Bool {
  match q {
    Some(x) => within(x.span, outer)
    None => true
  }
}

///|
fn part_span(p : @ast.PathPart) -> @ast.Span {
  match p {
    Node(n) => n.span
    Edge(e) => e.span
    Group(g) => g.span
  }
}

///|
fn part_spans_ok(p : @ast.PathPart) -> Bool {
  match p {
    Node(n) => element_spans_ok(n.variable, n.label, n.where_, n.span)
    Edge(e) =>
      quantifier_inside(e.quantifier, e.span) &&
      (match e.filler {
        Some(f) =>
          within(f.span, e.span) &&
          element_spans_ok(f.variable, f.label, f.where_, f.span)
        None => true
      })
    Group(g) => {
      let inner = [g.path.span]
      if g.where_ is Some(w) {
        inner.push(w.span)
      }
      ordered_within(inner, g.span) &&
      path_spans_ok(g.path) &&
      quantifier_inside(g.quantifier, g.span)
    }
  }
}

///|
fn path_spans_ok(p : @ast.PathPattern) -> Bool {
  let spans = match p.variable {
    Some(v) => [v.span]
    None => []
  }
  spans.append(p.parts.map(part_span))
  if !ordered_within(spans, p.span) {
    return false
  }
  for part in p.parts {
    if !part_spans_ok(part) {
      return false
    }
  }
  true
}

///|
/// Spec 10.2 law 4.
fn graph_spans_ok(m : @ast.GraphMatch, length : Int) -> Bool {
  let pattern = m.pattern
  let inner : Array[@ast.Span] = []
  if pattern.selector is Some(s) {
    inner.push(s.span)
  }
  inner.append(pattern.paths.map(p => p.span))
  if pattern.where_ is Some(w) {
    inner.push(w.span)
  }
  if !(within(m.span, { start: 0, end: length, }) &&
    ordered_within([m.graph.span, pattern.span], m.span) &&
    ordered_within(inner, pattern.span)) {
    return false
  }
  for p in pattern.paths {
    if !path_spans_ok(p) {
      return false
    }
  }
  true
}

///|
fn shape_or_error(source : String) -> String {
  expr_shape(source) catch {
    e => "error: \{e}"
  }
}

///|
test "law 1: graph patterns parse to the generated shape" {
  @quickcheck.check(
    (spec : GraphSpec) => {
      try shape_or_error(render(spec)) == expected_shape(spec) catch {
        _ => false
      }
    },
    count=500,
  )
}

///|
test "law 2: layout does not change the shape" {
  @quickcheck.check(
    (spec : GraphSpec) => {
      let plain = {
        ..spec,
        style: {
          ..spec.style,
          spacing: 1,
          case_: 0,
          full_labels: !spec.style.full_labels,
        },
      }
      shape_or_error(render(spec)) == shape_or_error(render(plain))
    },
    count=300,
  )
}

///|
test "law 3: the FROM form equals the parenthesized form" {
  @quickcheck.check(
    (spec : GraphSpec) => {
      let single = { ..spec, paths: [spec.paths[0]], where_: None, }
      let parenthesized = "SELECT * FROM " + render(single)
      try
        statement_shape(parenthesized) == statement_shape(render_from(spec))
      catch {
        _ => false
      }
    },
    count=300,
  )
}

///|
test "law 4: spans nest and do not overlap" {
  @quickcheck.check(
    (spec : GraphSpec) => {
      let source = render(spec)
      try @parser.parse_expression(source) catch {
        _ => false
      } noraise {
        { kind: GraphMatch(m), .. } => graph_spans_ok(m, source.length())
        _ => false
      }
    },
    count=300,
  )
}

///|
test "law 5: removing a closing delimiter is a syntax error" {
  @quickcheck.check(
    (spec : GraphSpec) => {
      let text = render(spec)
      for i in 0..<text.length() {
        let c = text.view(start_offset=i, end_offset=i + 1).to_owned()
        if c != ")" && c != "]" && c != "}" {
          continue
        }
        let cut = text.view(end_offset=i).to_owned() +
          text.view(start_offset=i + 1).to_owned()
        let syntax = try @parser.parse_statement(cut) catch {
          Syntax(..) => true
          _ => false
        } noraise {
          _ => false
        }
        if !syntax {
          return false
        }
      }
      true
    },
    count=200,
  )
}

///|
test "law 6: a pattern list in FROM parentheses keeps every path" {
  @quickcheck.check(
    (spec : GraphSpec) => {
      try
        statement_shape("SELECT * FROM " + render(spec)) ==
        "(select * (from \{expected_shape(spec)}))"
      catch {
        _ => false
      }
    },
    count=300,
  )
}

///|
test "law 9: printing a graph MATCH round-trips" {
  @quickcheck.check(
    (spec : GraphSpec) => {
      try {
        let first = @parser.parse_statement(render(spec))
        let printed = @printer.print(first)
        let second = @parser.parse_statement(printed)
        second.strip_spans() == first.strip_spans() &&
        @printer.print(second) == printed
      } catch {
        _ => false
      }
    },
    count=300,
  )
}
