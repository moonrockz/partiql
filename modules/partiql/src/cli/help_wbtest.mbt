///|
test "help_request finds -h and --help and the command before them" {
  @expect.expect(help_request(["-h"])).to_equal(Some([]))
  @expect.expect(help_request(["version", "--help"])).to_equal(
    Some(["version"]),
  )
  // A command with a required positional and no value: argparse alone
  // fails here; the pre-scan answers with that command's help.
  @expect.expect(help_request(["parse", "-h"])).to_equal(Some(["parse"]))
  @expect.expect(help_request(["version"])).to_equal(None)
  // After `--`, -h is a value, not a flag.
  @expect.expect(help_request(["parse", "--", "-h"])).to_equal(None)
}

///|
test "short_error keeps the error and usage lines" {
  let message =
    #|error: unexpected value 'x' found; no more were expected
    #|
    #|Usage: partiql [options] [command]
    #|
    #|PartiQL tools.
    #|
    #|Commands:
    #|  version  Print the version.
  @expect.expect(short_error(message)).to_equal(
    (
      #|partiql: unexpected value 'x' found; no more were expected
      #|Usage: partiql [options] [command]
      #|Run 'partiql help' for more information.
      #|
    ),
  )
}
