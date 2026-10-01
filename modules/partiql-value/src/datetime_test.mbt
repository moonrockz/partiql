///|
test "valid dates are accepted" {
  let d = @value.Date::new(year=2024, month=2, day=29)
  @expect.expect((d.year, d.month, d.day)).to_equal((2024, 2, 29))
}

///|
test "invalid dates raise" {
  for
    args in [
      (2023, 2, 29),
      (2024, 13, 1),
      (2024, 4, 31),
      (2024, 0, 1),
      (1900, 2, 29),
    ] {
    let (year, month, day) = args
    try @value.Date::new(year~, month~, day~) catch {
      @value.DateTimeError::InvalidDate(_) => ()
      other => fail("unexpected \{@debug.to_string(other)}")
    } noraise {
      _ => fail("accepted \{year}-\{month}-\{day}")
    }
  }
}

///|
test "time ranges" {
  let t = @value.Time::new(
    hour=23,
    minute=59,
    second=59,
    nanos=999999999,
    precision=9,
    offset=Some(-1439),
  )
  @expect.expect(t.nanos).to_equal(999999999)
  let bad : Array[() -> @value.Time raise @value.DateTimeError] = [
    () => @value.Time::new(hour=24, minute=0, second=0),
    () => @value.Time::new(hour=0, minute=60, second=0),
    () => @value.Time::new(hour=0, minute=0, second=60),
    () => {
      @value.Time::new(
        hour=0,
        minute=0,
        second=0,
        nanos=1000000000,
        precision=9,
      )
    },
    () => @value.Time::new(hour=0, minute=0, second=0, precision=10),
    () => @value.Time::new(hour=0, minute=0, second=0, nanos=5, precision=0),
    () => @value.Time::new(hour=0, minute=0, second=0, offset=Some(1440)),
  ]
  for make in bad {
    try make() catch {
      _ => ()
    } noraise {
      t => fail("accepted \{@debug.to_string(t)}")
    }
  }
}
