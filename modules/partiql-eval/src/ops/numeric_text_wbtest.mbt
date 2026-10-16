///|
/// The parse of `text` as a short string, so that one table checks all kinds.
fn parsed(text : String) -> String {
  try numeric_text(text) catch {
    TypeFailure(_) => "type"
    DataFailure(_) => "data"
    Unsupported(_) => "unsupported"
  } noraise {
    Whole(n) => "whole \{n}"
    Exact(d) => "exact \{d.coefficient()}e\{d.exponent()}"
    Approx(f) => "approx \{f}"
  }
}

///|
test "numeric_text: exact decimal forms" {
  @expect.expect_all(soft => {
    soft.expect(parsed("1")).to_equal("exact 1e0")
    soft.expect(parsed("  1.5 ")).to_equal("exact 15e-1")
    soft.expect(parsed("+1")).to_equal("exact 1e0")
    soft.expect(parsed("-12.50")).to_equal("exact -1250e-2")
    soft.expect(parsed(".5")).to_equal("exact 5e-1")
    soft.expect(parsed("1.")).to_equal("exact 1e0")
    soft.expect(parsed("007")).to_equal("exact 7e0")
    soft.expect(parsed("1_000")).to_equal("exact 1000e0")
    soft.expect(parsed("1_0.2_5")).to_equal("exact 1025e-2")
  })
}

///|
test "numeric_text: prefixed integers" {
  @expect.expect_all(soft => {
    soft.expect(parsed("0x1F")).to_equal("whole 31")
    soft.expect(parsed("0XA")).to_equal("whole 10")
    soft.expect(parsed("-0b101")).to_equal("whole -5")
    soft.expect(parsed("0o17")).to_equal("whole 15")
    soft.expect(parsed("0xFF_FF")).to_equal("whole 65535")
  })
}

///|
test "numeric_text: approximate forms" {
  @expect.expect_all(soft => {
    soft.expect(parsed("1.5e-3")).to_equal("approx 0.0015")
    soft.expect(parsed("2E10")).to_equal("approx 20000000000")
    soft.expect(parsed("-1e+2")).to_equal("approx -100")
    soft.expect(parsed("NaN")).to_equal("approx NaN")
    soft.expect(parsed("inf")).to_equal("approx Infinity")
    soft.expect(parsed("+INF")).to_equal("approx Infinity")
    soft.expect(parsed("-Inf")).to_equal("approx -Infinity")
    soft.expect(parsed("1e-400")).to_equal("approx 0")
    soft.expect(parsed("1e400")).to_equal("data")
  })
}

///|
test "numeric_text: text that is not a number" {
  @expect.expect_all(soft => {
    for
      text in [
        "", " ", "-", ".", "abc", "00xA", "0x", "0b2", "1 2", "1__0", "_1", "1_",
        "1e", "1e+", "+nan", "-nan", "1.2.3", "\t1",
      ] {
      soft.expect(parsed(text)).to_equal("type")
    }
  })
}
