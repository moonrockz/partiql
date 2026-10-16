///|
/// A UTC instant; `@time.date_time` raises only on bad fields.
fn utc(
  year : Int32,
  month : Int32,
  day : Int32,
  hour : Int32,
  minute : Int32,
  second : Int32,
  nanosecond : Int32,
) -> @time.ZonedDateTime raise {
  @time.date_time(year, month, day, hour~, minute~, second~, nanosecond~)
}

///|
fn ev_clock(
  source : String,
  clock : @eval.Clock?,
  zone~ : @eval.ZoneOffset = @eval.ZoneOffset::utc(),
  mode~ : @eval.Mode = Permissive,
) -> @value.Value raise @eval.EvalError {
  @eval.evaluate_text(source, env=@eval.Bindings::empty(), mode~, zone~, clock~)
}

///|
/// A clock that advances one second per call and counts its calls.
fn counting(calls : Ref[Int32]) -> @eval.Clock {
  {
    now: () => {
      calls.val += 1
      @time.unix(1700000000L + calls.val.to_int64())
    },
  }
}

///|
fn offset(minutes : Int32) -> @eval.ZoneOffset {
  @eval.ZoneOffset::new(minutes).unwrap_or(@eval.ZoneOffset::utc())
}

///|
test "clock functions read the injected clock in the session zone" {
  let clock = Some(@eval.Clock::fixed(utc(2026, 10, 16, 23, 30, 15, 123456789)))
  @expect.expect_all(soft => {
    soft
    .expect(ev_clock("CURRENT_DATE = DATE '2026-10-16'", clock))
    .to_equal(Bool(true))
    soft
    .expect(
      ev_clock("CURRENT_TIME = TIME WITH TIME ZONE '23:30:15+00:00'", clock),
    )
    .to_equal(Bool(true))
    soft
    .expect(
      ev_clock(
        "CURRENT_TIMESTAMP = TIMESTAMP '2026-10-16 23:30:15.123456+00:00'", clock,
      ),
    )
    .to_equal(Bool(true))
    soft
    .expect(ev_clock("EXTRACT(SECOND FROM CURRENT_TIMESTAMP)", clock))
    .to_equal(dec("15.123456"))
    soft
    .expect(ev_clock("EXTRACT(SECOND FROM CURRENT_TIMESTAMP(9))", clock))
    .to_equal(dec("15.123456789"))
    soft
    .expect(ev_clock("EXTRACT(SECOND FROM CURRENT_TIME)", clock))
    .to_equal(dec("15"))
    soft
    .expect(
      ev_clock("UTCNOW() = TIMESTAMP '2026-10-16 23:30:15.123456+00:00'", clock),
    )
    .to_equal(Bool(true))
    // +05:30 crosses midnight.
    soft
    .expect(
      ev_clock("CURRENT_DATE = DATE '2026-10-17'", clock, zone=offset(330)),
    )
    .to_equal(Bool(true))
    soft
    .expect(
      ev_clock(
        "EXTRACT(TIMEZONE_MINUTE FROM CURRENT_TIME)",
        clock,
        zone=offset(330),
      ),
    )
    .to_equal(Int(30))
    soft
    .expect(
      ev_clock("EXTRACT(HOUR FROM CURRENT_TIMESTAMP)", clock, zone=offset(-480)),
    )
    .to_equal(Int(15))
    soft
    .expect(
      ev_clock("EXTRACT(TIMEZONE_HOUR FROM UTCNOW())", clock, zone=offset(-480)),
    )
    .to_equal(Int(0))
  })
}

///|
test "clock values are cut, never rounded" {
  let clock = Some(@eval.Clock::fixed(utc(2026, 12, 31, 23, 59, 59, 999999999)))
  @expect.expect_all(soft => {
    soft
    .expect(
      ev_clock("CURRENT_TIME(0) = TIME WITH TIME ZONE '23:59:59+00:00'", clock),
    )
    .to_equal(Bool(true))
    soft
    .expect(ev_clock("CURRENT_DATE = DATE '2026-12-31'", clock))
    .to_equal(Bool(true))
  })
}

///|
test "the clock is read at most once per statement" {
  let calls = Ref(0)
  let clock = Some(counting(calls))
  @expect.expect_all(soft => {
    let rows = ev_clock(
      "SELECT VALUE [CURRENT_TIMESTAMP(9), (SELECT VALUE UTCNOW() FROM <<1>>), CURRENT_DATE] FROM <<1, 2, 3>>",
      clock,
    )
    soft.expect(calls.val).to_equal(1)
    soft
    .expect(
      ev_clock(
        "SELECT VALUE x FROM <<1, 2, 3>> AS x WHERE CURRENT_TIMESTAMP(9) = UTCNOW()",
        clock,
      ),
    )
    .to_equal(bag_of([Int(1), Int(2), Int(3)]))
    soft.expect(calls.val).to_equal(2)
    // WITH, GROUP BY and ORDER BY share the statement instant.
    soft
    .expect(
      ev_clock(
        "WITH t AS (SELECT VALUE CURRENT_TIMESTAMP(9) FROM <<1, 2>>) SELECT VALUE COUNT(*) FROM t AS x GROUP BY x = UTCNOW() ORDER BY CURRENT_DATE",
        clock,
      ),
    )
    .to_equal(@value.Value::List([Int(2)]))
    soft.expect(calls.val).to_equal(3)
    ignore(ev_clock("1 + 1", clock))
    soft.expect(calls.val).to_equal(3)
    guard rows is Bag(b) else { fail("rows") }
    let firsts = b.items().iter().map(r => r).collect()
    soft.expect(firsts.length()).to_equal(3)
    soft.expect(firsts[0] == firsts[1] && firsts[1] == firsts[2]).to_be_true()
  })
}

///|
test "no clock, a failing clock and the year limit are data errors" {
  let failing = @eval.Clock::{ now: () => raise Failure("no time source"), }
  let late = Some(@eval.Clock::fixed(utc(9999, 12, 31, 23, 0, 0, 0)))
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      for
        source in [
          "CURRENT_DATE", "CURRENT_TIME", "CURRENT_TIMESTAMP(3)", "UTCNOW()",
        ] {
        let outcome = try ev_clock(source, None, mode~) catch {
          DataError(message~, ..) => message
          _ => "other"
        } noraise {
          _ => "none"
        }
        soft
        .expect((source, outcome.contains("pass clock~ to evaluate")))
        .to_equal((source, true))
      }
      soft
      .expect(
        try ev_clock("CURRENT_DATE", Some(failing), mode~) catch {
          DataError(message~, ..) => message
          _ => "other"
        } noraise {
          _ => "none"
        },
      )
      .to_equal("the clock failed")
      soft
      .expect(
        try ev_clock("CURRENT_DATE", late, zone=offset(300), mode~) catch {
          DataError(..) => "data"
          _ => "other"
        } noraise {
          _ => "none"
        },
      )
      .to_equal("data")
    }
  })
}

///|
test "clock functions: static checks" {
  let clock = Some(@eval.Clock::fixed(utc(2026, 1, 1, 0, 0, 0, 0)))
  @expect.expect_all(soft => {
    for source in ["CURRENT_TIME(10)", "CURRENT_TIMESTAMP(12)", "UTCNOW(1)"] {
      let outcome = try ev_clock(source, clock) catch {
        DataError(..) => "data"
        _ => "other"
      } noraise {
        _ => "none"
      }
      soft.expect((source, outcome)).to_equal((source, "data"))
    }
  })
}

///|
test "CAST of TIME to TIMESTAMP takes CURRENT_DATE" {
  let clock = Some(@eval.Clock::fixed(utc(2026, 10, 16, 23, 30, 0, 0)))
  @expect.expect_all(soft => {
    soft
    .expect(
      ev_clock(
        "CAST(TIME '12:00:00' AS TIMESTAMP) = TIMESTAMP '2026-10-16 12:00:00'", clock,
      ),
    )
    .to_equal(Bool(true))
    soft
    .expect(
      ev_clock(
        "CAST(TIME WITH TIME ZONE '12:00:00+05:00' AS TIMESTAMP WITH TIME ZONE) = TIMESTAMP '2026-10-16 12:00:00+05:00'",
        clock,
      ),
    )
    .to_equal(Bool(true))
    // The date is CURRENT_DATE in the session zone.
    soft
    .expect(
      ev_clock(
        "CAST(TIME '01:00:00' AS TIMESTAMP) = TIMESTAMP '2026-10-17 01:00:00'",
        clock,
        zone=offset(330),
      ),
    )
    .to_equal(Bool(true))
    let outcome = try
      ev_clock("CAST(TIME '12:00:00' AS TIMESTAMP)", None, mode=Strict)
    catch {
      DataError(message~, ..) => message
      _ => "other"
    } noraise {
      _ => "none"
    }
    soft.expect(outcome.contains("pass clock~ to evaluate")).to_be_true()
  })
}
