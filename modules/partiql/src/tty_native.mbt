///|
extern "C" fn c_isatty(fd : Int32) -> Int32 = "isatty"

///|
/// Whether stderr is a terminal.
fn stderr_is_terminal() -> Bool {
  c_isatty(2) == 1
}
