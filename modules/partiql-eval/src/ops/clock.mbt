// The session clock (spec session-clock §5).

///|
/// Where "now" comes from. The library never reads a wall clock: the
/// composition root (the CLI's `main`) builds the real clock, and tests and
/// embedders pass fixed or fake ones. `now` may raise; the evaluator turns a
/// raise into a data error.
pub(all) struct Clock {
  now : () -> @time.ZonedDateTime raise
}

///|
/// A clock that always gives `at`.
pub fn Clock::fixed(at : @time.ZonedDateTime) -> Clock {
  { now: () => at, }
}

///|
/// The instant `seconds` (since 1970-01-01T00:00Z) and `nanos` seen at `zone`:
/// a timestamp with the zone's offset and `precision` fraction digits, cut,
/// never rounded. A date outside 0001-9999 is a datetime field overflow.
pub fn clock_timestamp(
  seconds : Int64,
  nanos : Int32,
  zone : ZoneOffset,
  precision : Int32,
) -> @value.Timestamp raise OpFailure {
  let shifted = big64(seconds) * nanos_per_second +
    big64(nanos.to_int64()) +
    minutes_nanos(zone.minutes)
  let (days, rest) = floor_split(shifted, nanos_per_day)
  if !fits_int64(days) {
    raise DataFailure("datetime field overflow: the clock is out of range")
  }
  let date = date_of_days(days.to_int64())
  let of_day = rest.to_int64()
  let second_of_day = (of_day / 1000000000L).to_int()
  let fraction = (of_day % 1000000000L).to_int()
  let unit = fraction_unit(precision)
  let time = @value.Time::new(
    hour=second_of_day / 3600,
    minute=second_of_day % 3600 / 60,
    second=second_of_day % 60,
    nanos=fraction - fraction % unit,
    precision~,
    offset=Some(zone.minutes),
  ) catch {
    _ => raise DataFailure("a time out of range")
  }
  @value.Timestamp::new(date, time)
}
