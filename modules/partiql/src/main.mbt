///|
fn main {
  let args = @env.args()
  let outcome = @cli.run(args[1:])
  if outcome.stdout != "" {
    println(outcome.stdout.trim_end(chars="\n"))
  }
  if outcome.stderr != "" {
    eprintln(outcome.stderr.trim_end(chars="\n"))
  }
  if outcome.status != 0 {
    @sys.exit(outcome.status)
  }
}
