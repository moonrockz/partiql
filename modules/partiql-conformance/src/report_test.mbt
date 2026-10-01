///|
/// Prints one machine-readable result line for the CI summary. Called
/// before the assertion, so a failed run still reports its counts.
fn report_conformance(
  suite~ : String,
  total~ : Int,
  passed~ : Int,
  not_applicable~ : Int,
  comparison~ : Comparison,
) -> Unit {
  let shown = comparison.regressions.iter().take(50).collect()
  let result : Json = {
    "suite": suite.to_json(),
    "total": total.to_json(),
    "passed": passed.to_json(),
    "not_applicable": not_applicable.to_json(),
    "regressions": comparison.regressions.length().to_json(),
    "new_passes": comparison.new_passes.length().to_json(),
    "regression_ids": shown.to_json(),
  }
  println("CONFORMANCE " + result.stringify())
}
