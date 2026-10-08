///|
test "LIKE" {
  @expect.expect_all(soft => {
    soft.expect(ev("'abc' LIKE 'a%'")).to_equal(Bool(true))
    soft.expect(ev("'abc' LIKE 'a_c'")).to_equal(Bool(true))
    soft.expect(ev("'abc' LIKE 'a_'")).to_equal(Bool(false))
    soft.expect(ev("'a%c' LIKE 'a\\%c' ESCAPE '\\'")).to_equal(Bool(true))
    soft.expect(ev("'😀' LIKE '_'")).to_equal(Bool(true))
    soft.expect(ev("'日本' || '😀'")).to_equal(String("日本😀"))
    soft.expect(ev("'abc' NOT LIKE 'b%'")).to_equal(Bool(true))
    soft.expect(ev("NULL LIKE 'a'")).to_equal(Null)
    soft.expect(ev("1 LIKE 'a'")).to_equal(Missing)
    soft
    .expect(ev("'" + "a".repeat(5000) + "' LIKE '" + "%a".repeat(50) + "%b'"))
    .to_equal(Bool(false))
  })
}

///|
test "LIKE absent operands and escape errors" {
  @expect.expect_all(soft => {
    soft.expect(ev("'a' LIKE NULL ESCAPE MISSING")).to_equal(Missing)
    soft.expect(ev("'a' LIKE 'a' ESCAPE NULL")).to_equal(Null)
    soft.expect(ev("MISSING NOT LIKE 'a'")).to_equal(Missing)
    soft.expect(ev("'' LIKE ''")).to_equal(Bool(true))
    soft.expect(ev("'_' LIKE '[_[_' ESCAPE '['")).to_equal(Bool(false))
    soft.expect(ev("'100%' LIKE '1_[%' ESCAPE '['")).to_equal(Bool(false))
    soft.expect(ev("'100%' LIKE '1__[%' ESCAPE '['")).to_equal(Bool(true))
    soft.expect(ev("123 LIKE 'a'")).to_equal(Missing)
  })
  let failed = fn(source : String, mode : @eval.Mode) -> Bool {
    try ev(source, mode~) catch {
      @eval.EvalError::DataError(..) => return true
      _ => return false
    } noraise {
      _ => false
    }
  }
  @expect.expect_all(soft => {
    soft.expect(failed("'a' LIKE 'a' ESCAPE 'aa'", Permissive)).to_be_true()
    soft.expect(failed("'a' LIKE 'a' ESCAPE 'aa'", Strict)).to_be_true()
    soft.expect(failed("'a' LIKE 'a[b' ESCAPE '['", Permissive)).to_be_true()
    soft.expect(failed("'a' LIKE 'a[' ESCAPE '['", Permissive)).to_be_true()
  })
}
