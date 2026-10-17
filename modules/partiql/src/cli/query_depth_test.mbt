///|
fn nested_result_query(depth : Int32) -> String {
  let sources = ["[1] AS v0"]
  for i in 1..<=depth {
    sources.push("[[v\{i - 1}]] AS v\{i}")
  }
  "SELECT VALUE v\{depth} FROM " + sources.join(", ")
}

///|
test "query writes a deeply nested computed result as compact Ion" {
  let depth = 10000
  let outcome = query(["--compact", "-e", nested_result_query(depth)])
  @expect.expect_all(soft => {
    soft.expect(outcome.status).to_equal(0)
    soft.expect(outcome.stderr).to_equal("")
    soft
    .expect(outcome.stdout)
    .to_equal("$bag::[" + "[".repeat(depth) + "1" + "]".repeat(depth) + "]\n")
  })
}

///|
test "query writes a deeply nested computed result as pretty Ion" {
  // Indentation grows quadratically with depth. This still exercises
  // the iterative path beyond the writer's 128-level fast path.
  let depth = 512
  let outcome = query(["-e", nested_result_query(depth)])
  @expect.expect_all(soft => {
    soft.expect(outcome.status).to_equal(0)
    soft.expect(outcome.stderr).to_equal("")
    soft.expect(outcome.stdout.has_prefix("$bag::[\n  [")).to_be_true()
    soft
    .expect(
      outcome.stdout.replace_all(old=" ", new="").replace_all(old="\n", new=""),
    )
    .to_equal("$bag::[" + "[".repeat(depth) + "1" + "]".repeat(depth) + "]")
  })
}
