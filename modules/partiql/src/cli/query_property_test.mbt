///|
/// A file that holds one value, bound with --data and printed by query,
/// reads back as the same value (spec M4e §8).
test "query --data t=F -e t prints back the value of F" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      let text = @text.write_ion(@partiql_ion.to_ion(a.value)) catch {
        _ => return false
      }
      let io : @cli.Io = {
        read_file: _ => text,
        write_file: (_, _) => (),
        read_stdin: () => "",
        color_default: false,
      }
      let outcome = @cli.run(["query", "--data", "t=v.ion", "-e", "t"], io~)
      let back = @text.read_ion_datagram(outcome.stdout) catch {
        _ => return false
      }
      match back {
        [ion] =>
          (@partiql_ion.from_ion(ion) catch { _ => return false }) == a.value
        _ => false
      }
    },
    count=200,
  )
}
