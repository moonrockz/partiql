///|
fn up(text : String) -> @value.Value raise OpFailure {
  upper([String(text)])
}

///|
fn low(text : String) -> @value.Value raise OpFailure {
  lower([String(text)])
}

///|
test "UPPER and LOWER use full, locale-independent case mapping" {
  @expect.expect_all(soft => {
    soft.expect(up("abc")).to_equal(String("ABC"))
    soft.expect(up("straße")).to_equal(String("STRASSE"))
    soft
    .expect(up("åß∂ƒ©˙∆˚¬…æ"))
    .to_equal(String("ÅSS∂Ƒ©˙∆˚¬…Æ"))
    soft.expect(up("ﬁﬂ")).to_equal(String("FIFL"))
    soft.expect(up("ǰ")).to_equal(String("J\u{030C}"))
    soft.expect(low("İ")).to_equal(String("i\u{0307}"))
    soft.expect(low("ABC")).to_equal(String("abc"))
    soft.expect(up("😁")).to_equal(String("😁"))
    soft.expect(upper([Null])).to_equal(Null)
    soft.expect(lower([Missing])).to_equal(Missing)
    soft.expect(failure(() => upper([Int(1)]))).to_equal("type")
  })
}

///|
test "LOWER applies Final_Sigma" {
  @expect.expect_all(soft => {
    soft.expect(low("ΣΑΣ")).to_equal(String("σας"))
    soft.expect(low("Σ")).to_equal(String("σ"))
    soft.expect(low("ΑΣ.")).to_equal(String("ας."))
    soft.expect(low("Α.Σ")).to_equal(String("α.ς"))
    soft.expect(low("ΑΣ\u{0301}Α")).to_equal(String("ασ\u{0301}α"))
    soft.expect(low("ΑΣ Α")).to_equal(String("ας α"))
  })
}

///|
test "case categories by ordinal" {
  @expect.expect_all(soft => {
    soft.expect(case_category('\u{01C5}') is Some(Lt)).to_be_true()
    soft.expect(case_category('\u{02B0}') is Some(Lm)).to_be_true()
    soft.expect(case_category('\u{0301}') is Some(Mn)).to_be_true()
    soft.expect(case_category('\u{20DD}') is Some(Me)).to_be_true()
    soft.expect(case_category('^') is Some(Sk)).to_be_true()
    soft.expect(case_category('\u{200B}') is Some(Cf)).to_be_true()
    soft.expect(case_category('a') is None).to_be_true()
  })
}
