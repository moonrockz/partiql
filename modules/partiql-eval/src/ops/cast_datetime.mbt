// CAST to DATE, TIME and TIMESTAMP (spec M4d2 §4.4, §5.4).

///|
/// Text as SQL reads it for CAST: leading and trailing spaces (U+0020) off.
fn trimmed(s : String) -> String {
  s.trim(chars=" ").to_owned()
}

///|
fn minutes_nanos(minutes : Int32) -> @bigint.BigInt {
  big64(minutes.to_int64() * 60L) * nanos_per_second
}

///|
/// `t` with its clock fields and the fraction `nanos` at `precision`, and
/// the offset `offset`.
fn clock(
  t : @value.Time,
  nanos~ : Int32,
  precision~ : Int32,
  offset~ : Int32?,
) -> @value.Time raise OpFailure {
  @value.Time::new(
    hour=t.hour,
    minute=t.minute,
    second=t.second,
    nanos~,
    precision~,
    offset~,
  ) catch {
    _ => raise DataFailure("a time out of range")
  }
}

///|
/// The SQL zone rule (SQL92 6.10 GR 10-11): a local time gets the session
/// offset when the target has a time zone; a time with an offset becomes
/// session local time when the target has none.
fn zoned_time(
  t : @value.Time,
  with_zone : Bool,
  session : ZoneOffset,
) -> @value.Time raise OpFailure {
  match (t.offset, with_zone) {
    (Some(_), true) | (None, false) => t
    (None, true) =>
      clock(
        t,
        nanos=t.nanos,
        precision=t.precision,
        offset=Some(session.minutes),
      )
    (Some(offset), false) => {
      let moved = time_shift(t, minutes_nanos(session.minutes - offset))
      clock(moved, nanos=moved.nanos, precision=moved.precision, offset=None)
    }
  }
}

///|
fn zoned_timestamp(
  ts : @value.Timestamp,
  with_zone : Bool,
  session : ZoneOffset,
) -> @value.Timestamp raise OpFailure {
  match (ts.time.offset, with_zone) {
    (Some(_), true) | (None, false) => ts
    (None, true) =>
      @value.Timestamp::new(
        ts.date,
        clock(
          ts.time,
          nanos=ts.time.nanos,
          precision=ts.time.precision,
          offset=Some(session.minutes),
        ),
      )
    (Some(offset), false) => {
      let moved = timestamp_shift(ts, minutes_nanos(session.minutes - offset))
      @value.Timestamp::new(
        moved.date,
        clock(
          moved.time,
          nanos=moved.time.nanos,
          precision=moved.time.precision,
          offset=None,
        ),
      )
    }
  }
}

///|
/// One unit in the last place of `p` fraction digits, in nanoseconds.
fn fraction_unit(p : Int32) -> Int32 {
  let mut unit = 1
  for _ in 0..<(9 - p) {
    unit = unit * 10
  }
  unit
}

///|
/// TIME(p): the fraction rounded half up to `p` digits; a carry wraps past
/// midnight. Without `p` the precision of the value stays.
fn time_precision(
  t : @value.Time,
  precision : Int32?,
) -> @value.Time raise OpFailure {
  guard precision is Some(p) else { return t }
  let unit = fraction_unit(p)
  let rest = t.nanos % unit
  let kept = clock(t, nanos=t.nanos - rest, precision=p, offset=t.offset)
  if rest > 0 && rest * 2 >= unit {
    time_shift(kept, big64(unit.to_int64()))
  } else {
    kept
  }
}

///|
/// TIMESTAMP(p): as TIME(p), with the carry into the date.
fn timestamp_precision(
  ts : @value.Timestamp,
  precision : Int32?,
) -> @value.Timestamp raise OpFailure {
  guard precision is Some(p) else { return ts }
  let unit = fraction_unit(p)
  let rest = ts.time.nanos % unit
  let kept = @value.Timestamp::new(
    ts.date,
    clock(
      ts.time,
      nanos=ts.time.nanos - rest,
      precision=p,
      offset=ts.time.offset,
    ),
  )
  if rest > 0 && rest * 2 >= unit {
    timestamp_shift(kept, big64(unit.to_int64()))
  } else {
    kept
  }
}

///|
fn to_date(
  x : @value.Value,
  session : ZoneOffset,
) -> @value.Value raise OpFailure {
  match x {
    Date(_) => x
    Timestamp(ts) => Date(zoned_timestamp(ts, false, session).date)
    String(s) => Date(parse_date(trimmed(s)))
    _ => raise TypeFailure("CAST of \{kind_name(x)} to DATE")
  }
}

///|
fn to_time(
  x : @value.Value,
  precision : Int32?,
  with_zone : Bool,
  session : ZoneOffset,
) -> @value.Value raise OpFailure {
  let t = match x {
    Time(t) => t
    Timestamp(ts) => ts.time
    String(s) => parse_time(trimmed(s), None, false)
    _ =>
      raise TypeFailure(
        "CAST of \{kind_name(x)} to \{target_name(Time(precision~, zone=with_zone))}",
      )
  }
  Time(time_precision(zoned_time(t, with_zone, session), precision))
}

///|
/// TIME to TIMESTAMP needs CURRENT_DATE, which this version does not have.
fn to_timestamp(
  x : @value.Value,
  precision : Int32?,
  with_zone : Bool,
  session : ZoneOffset,
) -> @value.Value raise OpFailure {
  let ts = match x {
    Timestamp(ts) => ts
    Date(d) =>
      @value.Timestamp::new(
        d,
        @value.Time::new(hour=0, minute=0, second=0, precision=0) catch {
          _ => raise DataFailure("a time out of range")
        },
      )
    String(s) => parse_timestamp(trimmed(s), None, false)
    Time(_) =>
      raise Unsupported("CAST of TIME to TIMESTAMP needs the current date")
    _ =>
      raise TypeFailure(
        "CAST of \{kind_name(x)} to \{target_name(Timestamp(precision~, zone=with_zone))}",
      )
  }
  Timestamp(
    timestamp_precision(zoned_timestamp(ts, with_zone, session), precision),
  )
}
