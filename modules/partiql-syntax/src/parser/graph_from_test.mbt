///|
test "graph MATCH as a FROM item" {
  check_queries([
    (
      "SELECT * FROM g MATCH (a)->(b)", "(select * (from (match g (path (node a) (edge ->) (node b)))))",
    ),
    (
      "SELECT * FROM g MATCH (a) AS x AT y", "(select * (from (match g (path (node a))) as x at y))",
    ),
    (
      "SELECT * FROM g MATCH ANY SHORTEST (a)->(b) WHERE a.x = 1", "(select * (from (match g any-shortest (path (node a) (edge ->) (node b)))) (where (= (path a .x) 1)))",
    ),
    (
      "SELECT * FROM g MATCH (a), t", "(select * (from (, (match g (path (node a))) t)))",
    ),
    (
      "SELECT * FROM g MATCH (a) JOIN h MATCH (b) ON true", "(select * (from (inner (match g (path (node a))) (match h (path (node b))) (on true))))",
    ),
  ])
}

///|
test "a comma inside parentheses continues the pattern list" {
  check_queries([
    (
      "SELECT * FROM (g MATCH (a), (b))", "(select * (from (match g (path (node a)) (path (node b)))))",
    ),
    (
      "SELECT * FROM (g MATCH (a), (b), (c))", "(select * (from (match g (path (node a)) (path (node b)) (path (node c)))))",
    ),
    (
      "SELECT * FROM (g MATCH (a) AS x, t)", "(select * (from (, (match g (path (node a))) as x t)))",
    ),
    (
      "SELECT * FROM (g MATCH (a)->(b) WHERE a.x = 1)", "(select * (from (match g (path (node a) (edge ->) (node b)) (where (= (path a .x) 1)))))",
    ),
    (
      "SELECT * FROM (g MATCH (a)) AS x", "(select * (from (match g (path (node a))) as x))",
    ),
    (
      "SELECT * FROM ( gpml MATCH WALK (a) -[ :Transfer]-> () -[ :Transfer]-> (a) )",
      "(select * (from (match gpml (path walk (node a) (edge -> [:Transfer]) (node) (edge -> [:Transfer]) (node a)))))",
    ),
  ])
}

///|
test "malformed FROM graph items fail" {
  check_query_failures([
    "SELECT * FROM g MATCH", "SELECT * FROM g MATCH (a) WHERE", "SELECT * FROM (g MATCH (a),)",
    "SELECT * FROM UNPIVOT g MATCH (a)",
  ])
}
