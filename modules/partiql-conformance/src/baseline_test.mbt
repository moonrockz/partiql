///|
test "compare finds regressions and new passes" {
  let c = compare(["a", "b"], ["b", "c"])
  @expect.expect(c.regressions).to_equal(["a"])
  @expect.expect(c.new_passes).to_equal(["c"])
}

///|
test "baseline text round-trips sorted and without blank lines" {
  @expect.expect(parse_baseline("b\n\na\n")).to_equal(["a", "b"])
  @expect.expect(format_baseline(["b", "a"])).to_equal("a\nb\n")
  @expect.expect(format_baseline([])).to_equal("")
}

///|
struct Comparison {
  regressions : Array[String]
  new_passes : Array[String]
}

///|
fn compare(baseline : Array[String], passed : Array[String]) -> Comparison {
  let passed_set = @hashset.from_array(passed)
  let baseline_set = @hashset.from_array(baseline)
  {
    regressions: baseline.filter(id => !passed_set.contains(id)),
    new_passes: passed.filter(id => !baseline_set.contains(id)),
  }
}

///|
fn parse_baseline(text : String) -> Array[String] {
  let ids = text
    .split("\n")
    // Only a line ending's `\r` is removed: test names may end with spaces.
    .map(line => line.strip_suffix("\r").unwrap_or(line).to_owned())
    .filter(line => line != "")
    .collect()
  ids.sort_by((a, b) => a.lexical_compare(b))
  ids
}

///|
fn format_baseline(ids : Array[String]) -> String {
  let sorted = ids.copy()
  // Lexicographic, so that the files sort like the `sort` command.
  sorted.sort_by((a, b) => a.lexical_compare(b))
  sorted.map(id => id + "\n").join("")
}

///|
fn baseline_path(check : String) -> String {
  "baseline/\{check}.txt"
}

///|
fn load_baseline(check : String) -> Array[String] raise {
  let path = baseline_path(check)
  if @fs.path_exists(path) {
    parse_baseline(@fs.read_file_to_string(path))
  } else {
    []
  }
}

///|
fn save_baseline(check : String, ids : Array[String]) -> Unit raise {
  @fs.write_string_to_file(baseline_path(check), format_baseline(ids))
}

///|
test "baseline ids keep trailing spaces" {
  // Some corpus test names end with a space.
  @expect.expect(parse_baseline("a \nb\r\n\n")).to_equal(["a ", "b"])
}
