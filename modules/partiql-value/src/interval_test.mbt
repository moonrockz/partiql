///|
test "year-month parts" {
  @expect.expect_all(soft => {
    let i = @value.IntervalYM::from_parts(negative=true, years=1L, months=14L)
    soft.expect(i.months).to_equal(-26L)
    soft
    .expect((i.is_negative(), i.years(), i.months_part()))
    .to_equal((true, 2L, 2L))
  })
}

///|
test "day-time normalizes" {
  let i = @value.IntervalDT::from_parts(
    negative=false,
    days=1L,
    hours=25L,
    minutes=61L,
    seconds=61L,
    nanos=1500000000L,
  )
  // 1d + 25h + 61m + 61s + 1.5s = 2d 2h 2m 2.5s
  @expect.expect(
    (i.days(), i.hours(), i.minutes(), i.seconds_part(), i.nanos_part()),
  ).to_equal((2L, 2L, 2L, 2L, 500000000L))
}

///|
test "negative day-time uses floor form and positive parts" {
  @expect.expect_all(soft => {
    let i = @value.IntervalDT::from_parts(
      negative=true,
      days=0L,
      hours=0L,
      minutes=0L,
      seconds=0L,
      nanos=500000000L,
    )
    soft.expect((i.seconds, i.nanos)).to_equal((-1L, 500000000))
    soft
    .expect((i.is_negative(), i.seconds_part(), i.nanos_part()))
    .to_equal((true, 0L, 500000000L))
  })
}

///|
test "zero is not negative" {
  let i = @value.IntervalDT::from_parts(
    negative=true,
    days=0L,
    hours=0L,
    minutes=0L,
    seconds=0L,
    nanos=0L,
  )
  @expect.expect(i.is_negative()).to_be_false()
}
