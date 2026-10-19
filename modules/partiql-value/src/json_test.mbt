///|
test "JSON preserves exact numbers, duplicate keys, and Unicode" {
  let source =
    #|{"a":9223372036854775808,"a":1.2300,"e":1e2,"nested":[true,false,null,"\uD83D\uDE00\n"]}
  let ion =
    #|{a:9223372036854775808,a:1.2300,e:1d2,nested:[true,false,null,"😀\n"]}
  let expected = @partiql_ion.read_text(ion)[0]
  @expect.expect_all(soft => {
    soft.expect(@partiql_json.read_text(source)).to_equal(expected)
    soft
    .expect(@partiql_json.read_bytes(@utf8.encode(source)))
    .to_equal(expected)
  })
}
