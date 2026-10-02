///|
test "graph MATCH" {
  check_prints([
    ("(g MATCH (a)-[e]->(b))", "(g MATCH (a) -[e]-> (b))"),
    ("(g MATCH (a)<-[e]-(b))", "(g MATCH (a) <-[e]- (b))"),
    ("(g MATCH (a)~[e]~(b))", "(g MATCH (a) ~[e]~ (b))"),
    ("(g MATCH (a)<~[e]~(b))", "(g MATCH (a) <~[e]~ (b))"),
    ("(g MATCH (a)~[e]~>(b))", "(g MATCH (a) ~[e]~> (b))"),
    ("(g MATCH (a)<-[e]->(b))", "(g MATCH (a) <-[e]-> (b))"),
    ("(g MATCH (a)-[e]-(b))", "(g MATCH (a) -[e]- (b))"),
    ("(g MATCH -> )", "(g MATCH ->)"),
    ("(g MATCH (a)- -(b))", "(g MATCH (a) - - (b))"),
    ("(g MATCH (a)<->(b))", "(g MATCH (a) <-> (b))"),
    ("(g MATCH ()-[]->())", "(g MATCH () -[]-> ())"),
    ("(g MATCH (x:A|B&!C WHERE x.n > 1))", "(g MATCH (x:A|B&!C WHERE x.n > 1))"),
    ("(g MATCH (x:(A|B)&C))", "(g MATCH (x:(A|B)&C))"),
    ("(g MATCH (x:!(!A)))", "(g MATCH (x:!(!A)))"),
    ("(g MATCH (:%))", "(g MATCH (:%))"),
    (
      "(g MATCH -[e:L WHERE e.w < 3]->+ (b))", "(g MATCH -[e:L WHERE e.w < 3]->+ (b))",
    ),
    (
      "(g MATCH (a)->{1,2}(b)->*(c)->{3,}(d))", "(g MATCH (a) ->{1,2} (b) ->* (c) ->{3,} (d))",
    ),
    (
      "(g match any shortest trail p = (a))", "(g MATCH ANY SHORTEST TRAIL p = (a))",
    ),
    ("(g MATCH ALL SHORTEST (a))", "(g MATCH ALL SHORTEST (a))"),
    ("(g MATCH ANY 2 (a))", "(g MATCH ANY 2 (a))"),
    ("(g MATCH SHORTEST 3 GROUP (a))", "(g MATCH SHORTEST 3 GROUP (a))"),
    ("(g MATCH SHORTEST (a))", "(g MATCH SHORTEST (a))"),
    ("(g MATCH (a), walk = (b))", "(g MATCH (a), walk = (b))"),
    (
      "(g MATCH [(a)->(b) WHERE a.x = 1]{1,2})", "(g MATCH [(a) -> (b) WHERE a.x = 1]{1,2})",
    ),
    ("(g MATCH ((a)))", "(g MATCH ((a)))"),
    ("(g MATCH (a)->(b) WHERE a.x = 1)", "(g MATCH (a) -> (b) WHERE a.x = 1)"),
    ("SELECT * FROM g MATCH (a) AS x", "SELECT * FROM (g MATCH (a)) AS x"),
    (
      "((SELECT VALUE g FROM t) MATCH (a))", "((SELECT VALUE g FROM t) MATCH (a))",
    ),
  ])
}
