///|
test "edges in every direction, full and abbreviated" {
  check_shapes([
    (
      "(g MATCH (a)<-[e]-(b))", "(match g (path (node a) (edge <- [e]) (node b)))",
    ),
    ("(g MATCH (a)~[e]~(b))", "(match g (path (node a) (edge ~ [e]) (node b)))"),
    (
      "(g MATCH (a)-[e]->(b))", "(match g (path (node a) (edge -> [e]) (node b)))",
    ),
    (
      "(g MATCH (a)<~[e]~(b))", "(match g (path (node a) (edge <~ [e]) (node b)))",
    ),
    (
      "(g MATCH (a)~[e]~>(b))", "(match g (path (node a) (edge ~> [e]) (node b)))",
    ),
    (
      "(g MATCH (a)<-[e]->(b))", "(match g (path (node a) (edge <-> [e]) (node b)))",
    ),
    ("(g MATCH (a)-[e]-(b))", "(match g (path (node a) (edge - [e]) (node b)))"),
    ("(g MATCH <-)", "(match g (path (edge <-)))"),
    ("(g MATCH ~)", "(match g (path (edge ~)))"),
    ("(g MATCH ->)", "(match g (path (edge ->)))"),
    ("(g MATCH <~)", "(match g (path (edge <~)))"),
    ("(g MATCH ~>)", "(match g (path (edge ~>)))"),
    ("(g MATCH <->)", "(match g (path (edge <->)))"),
    ("(g MATCH -)", "(match g (path (edge -)))"),
    ("(g MATCH ()-[]->())", "(match g (path (node) (edge -> []) (node)))"),
    (
      "(g MATCH (a) - [ e ] - > (b))", "(match g (path (node a) (edge -> [e]) (node b)))",
    ),
    ("(g MATCH (a) < - > (b))", "(match g (path (node a) (edge <->) (node b)))"),
    (
      "(g MATCH (a) /* c */ -> (b))", "(match g (path (node a) (edge ->) (node b)))",
    ),
    ("(g MATCH (a)--(b)\n)", "(match g (path (node a)))"),
  ])
}

///|
test "nodes and edge fillers" {
  check_shapes([
    ("(g MATCH ())", "(match g (path (node)))"),
    ("(g MATCH (x))", "(match g (path (node x)))"),
    ("(g MATCH (\"Q\"))", "(match g (path (node \"Q\")))"),
    ("(g MATCH (:L))", "(match g (path (node :L)))"),
    (
      "(g MATCH (x:L WHERE x.a = 1))", "(match g (path (node x :L (where (= (path x .a) 1)))))",
    ),
    (
      "(g MATCH (x WHERE x.n<-1))", "(match g (path (node x (where (< (path x .n) (neg 1))))))",
    ),
    (
      "(g MATCH (WHERE x.a = 1))", "(match g (path (node (where (= (path x .a) 1)))))",
    ),
    (
      "(g MATCH (a) -[ b:Transfer WHERE b.amount>9500000]-> ())", "(match g (path (node a) (edge -> [b :Transfer (where (> (path b .amount) 9500000))]) (node)))",
    ),
    ("(g MATCH -[ :Transfer]->)", "(match g (path (edge -> [:Transfer])))"),
  ])
}

///|
test "label expressions" {
  check_shapes([
    ("(g MATCH (x:A|B&C))", "(match g (path (node x :(| A (& B C)))))"),
    ("(g MATCH (x:A|B|C))", "(match g (path (node x :(| (| A B) C))))"),
    ("(g MATCH (x:A&B&C))", "(match g (path (node x :(& (& A B) C))))"),
    ("(g MATCH (x:!A&B))", "(match g (path (node x :(& (! A) B))))"),
    ("(g MATCH (x:!(A|B)))", "(match g (path (node x :(! (| A B)))))"),
    ("(g MATCH (x:!(!A)))", "(match g (path (node x :(! (! A)))))"),
    ("(g MATCH (x:%))", "(match g (path (node x :%)))"),
    ("(g MATCH (x:(A)))", "(match g (path (node x :A)))"),
    (
      "(g MATCH (c:City|Country))", "(match g (path (node c :(| City Country))))",
    ),
  ])
}

///|
test "edge quantifiers" {
  check_shapes([
    (
      "(g MATCH (a)-[e]->+(b))", "(match g (path (node a) (edge -> [e] +) (node b)))",
    ),
    ("(g MATCH (a)->*(b))", "(match g (path (node a) (edge -> *) (node b)))"),
    (
      "(g MATCH (a) -[:Transfer]->{3,3} (a))", "(match g (path (node a) (edge -> [:Transfer] {3,3}) (node a)))",
    ),
    (
      "(g MATCH (a)->{1,}(b))", "(match g (path (node a) (edge -> {1,}) (node b)))",
    ),
  ])
}

///|
test "malformed nodes, edges, labels and quantifiers fail" {
  check_failures([
    "(g MATCH (x:!!A))", "(g MATCH (x:A||B))", "(g MATCH (x:))", "(g MATCH (a)->{3,2}(b))",
    "(g MATCH (a)->{99999999999,}(b))", "(g MATCH (a)-[x->(b))", "(g MATCH (a)<~>(b))",
    "(g MATCH (a)-[x]~>(b))",
  ])
}

///|
test "restrictors and path variables" {
  check_shapes([
    (
      "(g MATCH TRAIL (a)->(b))", "(match g (path trail (node a) (edge ->) (node b)))",
    ),
    ("(g MATCH WALK (a))", "(match g (path walk (node a)))"),
    ("(g MATCH ACYCLIC (a))", "(match g (path acyclic (node a)))"),
    ("(g MATCH SIMPLE ->)", "(match g (path simple (edge ->)))"),
    ("(g MATCH p = (a))", "(match g (path p = (node a)))"),
    ("(g MATCH walk = (a))", "(match g (path walk = (node a)))"),
    ("(g MATCH TRAIL p = (a))", "(match g (path trail p = (node a)))"),
    ("(g MATCH TRAIL trail = (a))", "(match g (path trail trail = (node a)))"),
    ("(g MATCH \"trail\" = (a))", "(match g (path \"trail\" = (node a)))"),
    ("(g MATCH (trail))", "(match g (path (node trail)))"),
    ("(g MATCH (any))", "(match g (path (node any)))"),
  ])
}

///|
test "selectors" {
  check_shapes([
    ("(g MATCH ANY SHORTEST (a))", "(match g any-shortest (path (node a)))"),
    ("(g MATCH ALL SHORTEST (a))", "(match g all-shortest (path (node a)))"),
    ("(g MATCH SHORTEST (a))", "(match g shortest (path (node a)))"),
    ("(g MATCH SHORTEST 3 (a))", "(match g (shortest 3) (path (node a)))"),
    (
      "(g MATCH SHORTEST 3 GROUP (a))", "(match g (shortest 3 group) (path (node a)))",
    ),
    ("(g MATCH ANY (a))", "(match g any (path (node a)))"),
    ("(g MATCH ANY 2 (a))", "(match g (any 2) (path (node a)))"),
    ("(g MATCH ANY p = (a))", "(match g any (path p = (node a)))"),
    ("(g MATCH any = (a))", "(match g (path any = (node a)))"),
    ("(g MATCH ANY TRAIL (a))", "(match g any (path trail (node a)))"),
    (
      "(g match any shortest Trail (a) where a.x = 1)", "(match g any-shortest (path trail (node a)) (where (= (path a .x) 1)))",
    ),
  ])
}

///|
test "group patterns" {
  check_shapes([
    (
      "(g MATCH (a) (-[:isLocatedIn]->(c:City)))", "(match g (path (node a) (group paren (path (edge -> [:isLocatedIn]) (node c :City)))))",
    ),
    (
      "(g MATCH [(a)->(b)]+)", "(match g (path (group bracket (path (node a) (edge ->) (node b)) +)))",
    ),
    (
      "(g MATCH ((a)->(b) WHERE a.x = 1){1,2})", "(match g (path (group paren (path (node a) (edge ->) (node b)) (where (= (path a .x) 1)) {1,2})))",
    ),
    (
      "(g MATCH (TRAIL p = (a)->(b)))", "(match g (path (group paren (path trail p = (node a) (edge ->) (node b)))))",
    ),
    (
      "(g MATCH (((a))))", "(match g (path (group paren (path (group paren (path (node a)))))))",
    ),
    ("(g MATCH (->))", "(match g (path (group paren (path (edge ->)))))"),
    (
      "(g MATCH (a) - ((b)))", "(match g (path (node a) (edge -) (group paren (path (node b)))))",
    ),
  ])
}

///|
test "pattern lists, postfilter, operands" {
  check_shapes([
    ("(g MATCH (a), (b))", "(match g (path (node a)) (path (node b)))"),
    ("(g MATCH (a), p = (b))", "(match g (path (node a)) (path p = (node b)))"),
    (
      "(g MATCH (a)->(b) WHERE a.x = 1)", "(match g (path (node a) (edge ->) (node b)) (where (= (path a .x) 1)))",
    ),
    (
      "((SELECT VALUE g FROM t) MATCH (a))", "(match (select (value g) (from t)) (path (node a)))",
    ),
    ("(g.h MATCH (a))", "(match (path g .h) (path (node a)))"),
    ("1 + (g MATCH (a))", "(+ 1 (match g (path (node a))))"),
  ])
}

///|
test "malformed path patterns fail" {
  check_failures([
    "(g MATCH)", "(g MATCH p =)", "(g MATCH FOO (a))", "(g MATCH (a) WHERE)", "(g MATCH (a),)",
    "(g MATCH SHORTEST 2 GROUP)", "(g MATCH (a) -[(b)]-> (c))", "(g MATCH ((a))",
    "(g MATCH [(a))", "(g MATCH ANY 99999999999 (a))",
  ])
  check_query_failures(["SELECT g MATCH (a) FROM t"])
}

///|
test "a graph MATCH as the right side of IN" {
  check_shapes([
    ("x IN (g MATCH (a))", "(in x (match g (path (node a))))"),
    ("x NOT IN (g MATCH (a))", "(not-in x (match g (path (node a))))"),
  ])
}
