///|
/// Prints one machine-readable result line for the CI summary. Called
/// before the assertion, so a failed run still reports its counts.
fn report_conformance(
  suite~ : String,
  total~ : Int32,
  passed~ : Int32,
  not_applicable~ : Int32,
  comparison~ : Comparison,
) -> Unit {
  let shown = comparison.regressions.iter().take(50).collect()
  let result : Json = {
    "suite": Json(suite),
    "total": Json(total),
    "passed": Json(passed),
    "not_applicable": Json(not_applicable),
    "regressions": Json(comparison.regressions.length()),
    "new_passes": Json(comparison.new_passes.length()),
    "regression_ids": Json(shown),
  }
  println("CONFORMANCE " + result.stringify())
}
