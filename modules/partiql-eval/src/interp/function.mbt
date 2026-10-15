///|
/// Runs a built-in on evaluated arguments. Each `ops` function applies the
/// shared argument rule (spec M4d1 §4.3).
fn call(
  f : @plan.Function,
  args : Array[@value.Value],
) -> @value.Value raise @ops.OpFailure {
  match f {
    CharLength => @ops.char_length(args)
    OctetLength => @ops.octet_length(args)
    BitLength => @ops.bit_length(args)
  }
}
