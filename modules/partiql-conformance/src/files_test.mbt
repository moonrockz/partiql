///|
test "missing data root names the setup task" {
  try require_data_root("no-such-dir") catch {
    error =>
      @expect.expect(@debug.to_string(error)).to_contain("mise run setup")
  } noraise {
    _ => fail("expected an error")
  }
}

///|
/// The data roots, relative to the module root (the working directory of
/// `moon test`).
let data_roots : Array[String] = [
  "partiql-tests/partiql-tests-data", "partiql-tests/partiql-tests-data-extended",
]

///|
/// Fails with a setup hint when the submodule is not checked out.
fn require_data_root(root : String) -> Unit raise {
  if !@fs.path_exists(root) {
    fail(
      "\{root} is missing; run `mise run setup` to fetch the partiql-tests submodule",
    )
  }
}

///|
/// Every `.ion` file under `dir`, recursively, in a stable order. The `.isl`
/// schema file is left out by the suffix.
fn ion_files_under(dir : String) -> Array[String] raise {
  let files : Array[String] = []
  let entries = @fs.read_dir(dir).to_owned()
  entries.sort()
  for entry in entries {
    let path = dir + "/" + entry
    if @fs.is_dir(path) {
      files.append(ion_files_under(path))
    } else if path.has_suffix(".ion") {
      files.push(path)
    }
  }
  files
}
