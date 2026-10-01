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
