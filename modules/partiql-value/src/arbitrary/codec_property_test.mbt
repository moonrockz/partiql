///|
test "decode inverts encode" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      @partiql_ion.from_ion(@partiql_ion.to_ion(a.value)) == a.value
    },
    count=200,
  )
}

///|
test "encoding is a fixpoint after one round trip" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      let once = @partiql_ion.to_ion(a.value)
      @partiql_ion.to_ion(@partiql_ion.from_ion(once)).equals(once)
    },
    count=200,
  )
}

///|
test "decode never aborts" {
  @quickcheck.check(
    (a : @arbitrary.ArbIon) => {
      try @partiql_ion.from_ion(a.value) catch {
        _ => true
      } noraise {
        _ => true
      }
    },
    count=200,
  )
}
