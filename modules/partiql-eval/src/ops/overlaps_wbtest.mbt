///|
fn ov(x : @value.Value, y : @value.Value) -> @value.Value raise OpFailure {
  overlaps([x, y], zone=ZoneOffset::utc())
}

///|
fn jan(day : Int32) -> @value.Value {
  try @value.Value::from_date(@value.Date(year=2023, month=1, day~)) catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
fn pair(a : @value.Value, b : @value.Value) -> @value.Value {
  @value.Value::from_list([a, b])
}

///|
fn days(n : Int64) -> @value.Value {
  try @value.Value::from_interval_dt(@value.IntervalDT(n * 86400L, 0L)) catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
test "OVERLAPS follows SQL-92 8.11" {
  @expect.expect_all(soft => {
    soft
    .expect(ov(pair(jan(1), jan(10)), pair(jan(5), jan(20))))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ov(pair(jan(1), jan(10)), pair(jan(10), jan(20))))
    .to_equal(@value.Value::from_bool(false))
    soft
    .expect(ov(pair(jan(10), jan(1)), pair(jan(5), jan(6))))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ov(pair(jan(15), jan(15)), pair(jan(15), jan(15))))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ov(pair(jan(1), days(9)), pair(jan(5), days(1))))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ov(pair(jan(10), days(-9)), pair(jan(5), jan(6))))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(
      ov(
        @value.Value::from_bag(@value.Bag([jan(1), jan(10)])),
        pair(jan(5), jan(6)),
      ),
    )
    .to_equal(@value.Value::from_bool(true))
  })
}

///|
test "OVERLAPS with NULL and MISSING" {
  @expect.expect_all(soft => {
    soft.expect(ov(Null, pair(jan(1), jan(2)))).to_equal(Null)
    soft.expect(ov(Null, Missing)).to_equal(Missing)
    soft.expect(ov(pair(jan(1), jan(2)), Missing)).to_equal(Missing)
    // overlaps.ion:491 and :503.
    soft
    .expect(ov(pair(Null, jan(15)), pair(jan(1), jan(31))))
    .to_equal(@value.Value::from_bool(true))
    soft.expect(ov(pair(Null, jan(1)), pair(jan(15), jan(31)))).to_equal(Null)
    soft
    .expect(ov(pair(Missing, jan(15)), pair(jan(1), jan(31))))
    .to_equal(@value.Value::from_bool(true))
    // S1 = S2 with an unknown end: SQL's third disjunct is UNKNOWN.
    soft.expect(ov(pair(jan(1), Null), pair(jan(1), jan(5)))).to_equal(Null)
  })
}

///|
test "OVERLAPS shape and type failures" {
  @expect.expect_all(soft => {
    soft
    .expect(
      failure(() => ov(@value.Value::from_list([jan(1)]), pair(jan(1), jan(2)))),
    )
    .to_equal("type")
    soft
    .expect(
      failure(() => {
        ov(
          @value.Value::from_list([jan(1), jan(2), jan(3)]),
          pair(jan(1), jan(2)),
        )
      }),
    )
    .to_equal("type")
    soft
    .expect(
      failure(() => ov(@value.Value::from_string("x"), pair(jan(1), jan(2)))),
    )
    .to_equal("type")
    soft
    .expect(
      failure(() => {
        ov(pair(Null, @value.Value::from_int(1)), pair(jan(1), jan(2)))
      }),
    )
    .to_equal("type")
    soft
    .expect(
      failure(() => {
        ov(pair(@value.Value::from_int(42), Null), pair(jan(1), jan(2)))
      }),
    )
    .to_equal("type")
    let noon = try
      @value.Value::from_time(@value.Time(hour=12, minute=0, second=0))
    catch {
      _ => @value.Value::Missing
    } noraise {
      v => v
    }
    soft
    .expect(failure(() => ov(pair(noon, noon), pair(jan(1), jan(2)))))
    .to_equal("type")
  })
}

///|
test "OVERLAPS over Ion timestamps" {
  let a = @value.Value::from_ion(
    @ion_core.IonValue::timestamp(@ion_core.Timestamp::Timestamp(year=2020)),
  )
  let b = @value.Value::from_ion(
    @ion_core.IonValue::timestamp(@ion_core.Timestamp::Timestamp(year=2022)),
  )
  @expect.expect_all(soft => {
    soft
    .expect(
      ov(
        @value.Value::from_ion(
          @ion_core.IonValue::list([
            @ion_core.IonValue::timestamp(
              @ion_core.Timestamp::Timestamp(year=2020),
            ),
            @ion_core.IonValue::timestamp(
              @ion_core.Timestamp::Timestamp(year=2022),
            ),
          ]),
        ),
        pair(a, b),
      ),
    )
    .to_equal(@value.Value::from_bool(true))
  })
}
