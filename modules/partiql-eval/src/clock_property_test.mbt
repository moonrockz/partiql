///|
test "law: the clock functions agree for random instants and zones" {
  let rs = @splitmix.RandomState(seed=23UL)
  @expect.expect_all(soft => {
    for _ in 0..<200 {
      // 1970..2100, any nanosecond, a zone in -12:00..+14:00 in 15 minutes.
      let seconds = (rs.next_uint().to_int64() % 4102444800L).abs()
      let nanos = pick(rs, 1000000000)
      let zone = offset((pick(rs, 105) - 48) * 15)
      let at = @time.unix(seconds, nanosecond=nanos) catch { _ => continue }
      let clock = Some(@eval.Clock::fixed(at))
      for
        law in [
          "CURRENT_TIMESTAMP = UTCNOW()", "CAST(CURRENT_TIMESTAMP AS DATE) = CURRENT_DATE",
          "CAST(CURRENT_TIMESTAMP AS TIME WITH TIME ZONE) = CURRENT_TIME(6)",
        ] {
        soft
        .expect((law, seconds, nanos, ev_clock(law, clock, zone~)))
        .to_equal((law, seconds, nanos, Bool(true)))
      }
    }
  })
}
