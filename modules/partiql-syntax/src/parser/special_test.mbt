///|
test "CASE" {
  check_shapes([
    ("CASE WHEN a THEN 1 END", "(case (when a 1))"),
    (
      "CASE x WHEN 1 THEN 'a' WHEN 2 THEN 'b' ELSE 'c' END", "(case x (when 1 'a') (when 2 'b') (else 'c'))",
    ),
  ])
  check_failures([
    "CASE END", "CASE ELSE 1 END", "CASE name ELSE 1 END", "CASE WHEN a THEN 1",
  ])
}

///|
test "CAST and types" {
  check_shapes([
    ("CAST(a AS INT)", "(cast a INT)"),
    ("cast(NULL AS MISSING)", "(cast null MISSING)"),
    ("CAST(a AS DECIMAL(5,2))", "(cast a DECIMAL(5,2))"),
    ("CAST(a AS VARCHAR(3))", "(cast a VARCHAR(3))"),
    ("CAST(a AS CHARACTER VARYING(3))", "(cast a VARCHAR(3))"),
    ("CAST(a AS DOUBLE PRECISION)", "(cast a DOUBLE)"),
    ("CAST(a AS TIME(3) WITH TIME ZONE)", "(cast a TIME(3) TZ)"),
    ("CAST(a AS INTERVAL DAY TO HOUR)", "(cast a INTERVAL day to hour)"),
    ("CAST(a AS INTERVAL YEAR(3))", "(cast a INTERVAL year(3))"),
    ("CAST(a AS INTERVAL SECOND(3,3))", "(cast a INTERVAL second(3,3))"),
    (
      "CAST(a AS MAP<STRING, MAP<INT, INT>>)", "(cast a MAP<STRING,MAP<INT,INT>>)",
    ),
    ("CAST(a AS BOOLEAN)", "(cast a BOOL)"),
  ])
  check_failures([
    "CAST 5 as integer", "CAST(5 AS SELECT)", "CAST(5 AS)", "CAST(5 INT)",
  ])
}

///|
test "EXTRACT, TRIM, SUBSTRING, POSITION, OVERLAY" {
  check_shapes([
    ("EXTRACT(YEAR FROM d)", "(extract year d)"),
    ("extract(timezone_hour FROM t)", "(extract timezone_hour t)"),
    ("TRIM(x)", "(trim x)"),
    ("TRIM(BOTH FROM x)", "(trim both x)"),
    ("TRIM(LEADING 'a' FROM x)", "(trim leading 'a' x)"),
    ("trim('a' FROM x)", "(trim 'a' x)"),
    ("SUBSTRING(s, 2)", "(substring s 2)"),
    ("SUBSTRING(s, 2, 3)", "(substring s 2 3)"),
    ("SUBSTRING(s FROM 2 FOR 3)", "(substring s 2 3)"),
    ("POSITION('a' IN s)", "(position 'a' s)"),
    ("POSITION('a', s)", "(position 'a' s)"),
    ("OVERLAY(s PLACING 'x' FROM 2 FOR 3)", "(overlay s 'x' 2 3)"),
    ("OVERLAY(s PLACING 'x' FROM 2)", "(overlay s 'x' 2)"),
    ("COALESCE(a, b, c)", "(coalesce a b c)"),
    ("NULLIF(a, b)", "(nullif a b)"),
    ("DATE_ADD(day, 1, d)", "(date_add day 1 d)"),
    ("DATE_DIFF(year, a, b)", "(date_diff year a b)"),
  ])
  check_failures([
    "EXTRACT(YEAR d)", "EXTRACT(FROM d)", "SUBSTRING(s", "SUBSTRING(s FROM)", "SUBSTRING(s 2)",
    "POSITION('abc')", "POSITION(IN 'x')", "TRIM ' ')", "trim(both '' 'test')", "NULLIF(a)",
  ])
}

///|
test "datetime and interval literals" {
  check_shapes([
    ("DATE '2012-08-28'", "(date '2012-08-28')"),
    ("TIME '23:59:59'", "(time '23:59:59')"),
    (
      "TIME(3) WITH TIME ZONE '23:59:59.123+01:00'", "(time(3) tz '23:59:59.123+01:00')",
    ),
    ("TIME WITH TIME ZONE'02:30:59'", "(time tz '02:30:59')"),
    ("TIME WITHOUT TIME ZONE '02:30:59'", "(time '02:30:59')"),
    ("TIMESTAMP '2007-02-23 12:14:33'", "(timestamp '2007-02-23 12:14:33')"),
    ("INTERVAL '+5' YEAR", "(interval '+5' year)"),
    ("INTERVAL -'1-2' YEAR TO MONTH", "(interval -'1-2' year to month)"),
    ("INTERVAL '1' SECOND(3, 3)", "(interval '1' second(3,3))"),
  ])
  check_failures([
    "DATE", "DATE 2012", "DATE `2012-08-28`", "DATE 'x", "TIME WITH TIMEZONE '1'",
    "TIME WITH TIME PHONE '1'", "TIME [4] '1'", "TIME {4} '1'", "TIME 4 '1'", "INTERVAL '1'",
  ])
}

///|
test "TRIM with FROM only; no empty parentheses" {
  check_shapes([
    ("trim(from '  x ')", "(trim '  x ')"),
    ("[({'a': 1})]", "[{'a':1}]"),
  ])
  check_failures(["[()]", "()"])
}
