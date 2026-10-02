///|
test "print_script writes leftover comments at the end" {
  let script = @parser.parse_script("SELECT 1 /* a */ /* b */")
  @expect.expect(@printer.print_script(script)).to_equal(
    "SELECT 1;\n/* a */\n/* b */\n",
  )
}
