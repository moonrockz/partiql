# Conformance

## Sources

- Suite: [partiql/partiql-tests](https://github.com/partiql/partiql-tests),
  license Apache-2.0.
- Location: git submodule `modules/partiql-conformance/partiql-tests`.
- Pinned commit: `2ef0ce2` (2026-06-29, "Add MAP conformance tests").
  partiql-tests has no tags, so the pin is a commit.
- Data roots: `partiql-tests-data` and `partiql-tests-data-extended`.

## How to run

```bash
mise run setup              # fetch the submodule
mise run test:conformance   # run the suite against the baseline
```

The harness prints one line per check:

```
CONFORMANCE {"suite":"syntax","total":672,"passed":0,"not_applicable":247,"regressions":0,"new_passes":0,"regression_ids":[]}
```

CI turns these lines into a job summary (`.github/scripts/conformance_summary.py`).

## Checks

| Check | Test cases | Pass condition |
|---|---|---|
| `syntax` | `SyntaxSuccess` | `parse` succeeds |
| `syntax` | `SyntaxFail` | `parse` raises `ParseError::Syntax` |
| `syntax` | `StaticAnalysisFail` | not applicable yet (counted as N/A) |
| `eval-parse` | `EvaluationSuccess`, `EvaluationFail` | the statement parses |
| `codec` | each `env` and each `EvaluationSuccess` `output` | `v = from_ion(x)` succeeds; `from_ion(to_ion(v)) == v` (structural identity); `to_ion` is a fixpoint after one round trip; and the binary datagram round-trip preserves `v` |
| `ion-roundtrip` | each `$ion::` value inside a corpus value | it decodes to an `Ion` value and encodes back to an Ion-equal value |
| `print-roundtrip` | each `SyntaxSuccess` and evaluation statement | parsing the printed statement gives the same tree (spans aside), and printing it again gives the same text; a statement that does not parse is N/A |
| `pretty-roundtrip` | each `SyntaxSuccess` and evaluation statement | the same as `print-roundtrip`, with the pretty layout at width 40 |
| `recovery` | each `SyntaxSuccess`, `SyntaxFail` and evaluation statement | if the strict `parse_script` succeeds, `parse_script_recovering` gives the same tree and no errors; if it raises, the recovered errors include its error |
| `eval` | each assertion of an `EvaluationSuccess` or `EvaluationFail` case, once per mode | see below |

`ParseError::Unsupported` and `CodecError::Unsupported` always count as
failures.

The `codec` check does not require the encoded Ion to equal the input Ion:
the reference runners decode Ion symbols as strings and accept legacy
`$date`/`$time` forms, so the encoder writes strings and the new canonical
forms (see ADR 0005).

### The `eval` check

The check evaluates each statement with the case's `env`. A case has one
assertion per typing mode. The check runs every assertion in its mode:
permissive (`EvalModeCoerce`) or strict (`EvalModeError`). One test id exists
per assertion and mode: `<id>#coerce` or `<id>#error`.

- An `EvaluationSuccess` assertion passes when the result equals the expected
  `output`.
- An `EvaluationFail` assertion passes when evaluation raises `TypeError` or
  `DataError`.
- A result of `EvalError::Unsupported` is recorded as not applicable. It is
  never a pass and never an expected error. The not-applicable set shrinks
  as later parts of M4 add queries, functions and CAST.
- `eval-equiv` cases are evaluated since M4b2. Each statement of the
  equivalence class runs against the case's assertions. The ids are
  `<case id>[<i>]#coerce` and `<case id>[<i>]#error`, with `i` from 0.

Two cases (`eval/primitives/map.ion`, lines 850 and 1194) expect a DATE
written as a plain Ion timestamp. Line 1194 ("unpivot map with date keys")
runs since M4b1 and line 850 ("map_keys with date keys") since M4d1. Both
fail in both modes, because the comparison does not treat a DATE and a
midnight UTC TIMESTAMP as equal yet.

A test case whose `statement` names an `equiv_class` is checked once per
statement of that class (ids end in `[0]`, `[1]`, ...). Test ids have the form
`<file>::<namespace>::...::<name>`. A repeated id gets the suffix `#2`, `#3`,
....

## Ratchet

- `modules/partiql-conformance/baseline/<check>.txt` lists the passing test
  ids, one per line, sorted.
- A baseline id that fails is a regression. A regression fails the test.
- A passing id that is not in the baseline is a new pass. New passes do not
  fail the test, but CI fails when the baseline is out of date.
- After a change that makes tests pass, run `mise run conformance:ratchet`
  and commit the baseline in the same commit.
- The ratchet never drops a baseline id. When a baseline id fails, the ratchet
  fails and keeps the baseline. To drop ids on purpose (for example when a pin
  bump removes tests), set `PARTIQL_CONFORMANCE_ALLOW_DROP=1`.
- To list the failures of one check with their reasons, set
  `PARTIQL_CONFORMANCE_SHOW=<check>` (for example `eval`) when you run
  `mise run test:conformance`.
- Never edit the baseline by hand. Never remove an id to hide a regression.

## Updating the pin

```bash
git -C modules/partiql-conformance/partiql-tests fetch
git -C modules/partiql-conformance/partiql-tests checkout <commit>
mise run test:conformance        # read the regressions, if any
# Only when the new pin removed or renamed tests:
PARTIQL_CONFORMANCE_ALLOW_DROP=1 mise run conformance:ratchet
git add modules/partiql-conformance
git commit -m "test(conformance): bump partiql-tests to <short sha>"
```

Update the pinned commit in this file too.

## Encodings

The test files write PartiQL values that Ion cannot express as annotated Ion
("PartiQL-encoded Ion"):

| Value | Encoding |
|---|---|
| MISSING | `$missing::null` |
| bag | `$bag::[...]` |
| date | `$date::{year, month, day}` (legacy: `$date::2021-08-22`) |
| time | `$time::{hour, minute, second, offset}` (legacy: `timezone_hour`/`timezone_minute` fields, or `$time::"04:05:06"`) |
| timestamp | `$timestamp::{year, month, day, hour, minute, second, offset}` |
| intervals | `$interval_ym::{...}`, `$interval_dt::{...}` |
| map | `$map::<key type>::<value type>::[[k, v], ...]` |
| graph | `$graph::{nodes, edges}` |
| Ion-typed value | `$ion::...` |

Both the legacy and the new `$date` and `$time` forms occur in the pinned
files, so the codec must accept both.

## Current status

After M1 (data model), M1b (MAP and graph), M2 (parser), M2b (graph
MATCH), M3a (printer), M3b (pretty layout), M3d (error recovery), M4a
(expression evaluation), M4b1 (query evaluation core), M4b2 (queries,
part two), M4c (grouping and aggregates), M4d1 (built-in functions), M4d2
(CAST), M4d3 (datetime functions) and ambiguous lookup checks:

| Check | Passed | Total | N/A |
|---|---|---|---|
| `syntax` | 425 | 672 | 247 |
| `eval-parse` | 4982 | 4985 | 0 |
| `codec` | 6822 | 6822 | 0 |
| `ion-roundtrip` | 39 | 39 | 0 |
| `print-roundtrip` | 5310 | 5313 | 3 |
| `pretty-roundtrip` | 5310 | 5313 | 3 |
| `recovery` | 5410 | 5410 | 0 |
| `eval` | 9604 | 9960 | 240 |

The 3 `eval-parse` failures are corpus defects (bead `partiql-zhj.9`):

- `eval/query/group-by/group-by.ion` "max and min of rep grouped by
  fiscal_year": `SELECT max(rep), min(rep)) FROM ...` has a stray `)`.
- `eval/primitives/functions/cardinality.ion` (the case with `()`): an empty
  `()` is not PartiQL (the Kotlin grammar has no such expression, and
  `fail/syntax` requires `SELECT () FROM data` to fail).
- `eval-equiv/spec-tests.ion` "equiv coercion of a SELECT subquery into a
  scalar" `[1]`: a struct with a missing comma.

### The `eval` check

Of 9960 assertions, 9604 pass and 240 are not applicable: they need graph
MATCH, which comes after M4 (the eval corpus has no FULL JOIN and no `?`
statement). 116 fail. M4b1 raised the passes from 2952 to 3719, M4b2 raised them
to 4043 (324 more), with the `eval-equiv` cases now evaluated, M4c raised
them to 5211 (1168 more), M4d1 raised them to 7287 (2076 more), M4d2
raised them to 7507 (220 more), M4d3 raised them to 9601 (2094 more), and
ambiguous lookup checks raised them to 9604 (3 more). To list the
failures, run `PARTIQL_CONFORMANCE_SHOW=eval mise run test:conformance`. Each
case fails in both modes, except where a reason below says otherwise. The
reasons:

- **Corpus defects (6 ids).** `cardinality.ion` (the case with `()`) and
  `group-by.ion` "max and min of rep grouped by fiscal_year" do not parse
  (see the `eval-parse` defects above). `select.ion` `selectDistinctExpression`
  writes strings as `"1"`, which is a quoted identifier, so the name is
  undefined.
- **Undefined variable (3 ids).** The two `path.ion` cases "subscript with
  non-existent variable" and the `spec-tests.ion` case "data type mismatch in
  logical expression" (permissive mode) expect MISSING. The dedicated cases in
  `undefined-variable-behavior.ion` expect an error in both modes, and the
  evaluator follows them: with no FROM variable in scope, an undefined name is
  a `DataError`.
- **IN with a non-collection right side (1 id).** `inPredicateSingleExpr`
  expects `b.price IN 5` to succeed in strict mode, while
  `notInPredicateSingleExpr` expects `b.price NOT IN 5` to fail. The
  evaluator raises a `TypeError`, so the NOT IN case passes and this one
  fails (spec M4b1, section 9).
- **Outer join padding (6 ids).** `select.ion` `selectCorrelatedLeftJoin` and
  `selectCorrelatedLeftJoinOnClause`, and `joins.ion` `PG_JOIN_09`, expect the
  padded side of a LEFT JOIN to be a tuple of NULL attributes (`b.title` is
  NULL; `SELECT *` lists the attributes). The evaluator pads the variable with
  NULL, so the attribute is MISSING. This needs the schema of the padded
  side (bead `partiql-5se.12`).
- **Interval times or divided by a number (14 ids).** `INTERVAL '2' DAY * 50`,
  `INTERVAL '3' YEAR * 50`, `INTERVAL '2' DAY / 0.02` and
  `INTERVAL '3' YEAR / 0.03` expect a failure because the result has more
  than two leading digits. The value model keeps no leading precision, and the
  specification marks this case as unsettled (partiql-lang#100), so the
  evaluator returns the exact result and does not cap it (8 ids). The
  three `/ 2.25e-1` cases (6 ids) expect a floating-point
  division. An exponent literal is a DECIMAL here, so the division is exact
  and gives a different result. These pass when approximate literals are
  modelled.
- **TIME and TIMESTAMP "explicit ... with offset - failure" (4 ids).** The
  corpus expects `TIME WITHOUT TIME ZONE '...+01:00'` to fail. The parser
  does not keep WITHOUT TIME ZONE apart, so this needs a parser change.
- **DECIMAL(p,s) IS-type (4 ids).** `1.000 IS DECIMAL(3,3)` and
  `123.456 IS DECIMAL(7,3)` expect results that do not agree with the rules for
  precision and scale that the other cases of the corpus follow.
- **DATE against Ion timestamp (2 ids).** "unpivot map with date keys" gives
  DATE keys, and the corpus writes them as Ion timestamps. The comparison of
  the harness does not treat a DATE and a midnight UTC TIMESTAMP as equal.
  "map_keys with date keys" fails for the same reason since M4d1 (counted
  under M4d1).
- **`a.*.*.*.*` in strict mode (1 id).** `pathUnpivotWildCardOverStructMultiple`
  expects a failure. Every `.*` step applies to a tuple, so the evaluator
  succeeds; the corpus expectation is taken as an artifact.

M4b2 adds 24 failing ids in three groups:

- **Corpus defects (17 ids).**
  - `order-by.ion` "structs should be ordered by data types (DESC)": the
    statement has the empty struct `{}`, and the expected output has the
    empty blob `{{}}` (2 ids).
  - `eval-equiv/spec-tests.ion` has 15 ids with wrong or contradictory
    cases. Section 12 "explicit literals" expects `9 < '10'` to succeed in
    strict mode, and expects `SELECT * FROM foo` with a scalar `foo` to
    succeed in strict mode (3 ids). Three statements cannot fail in strict
    mode but share a class with a failing assertion: section 4 wildcard
    steps `[1]`, section 5 unpivot missing `[1]` and unpivot non-missing
    `[1]` (3 ids). Section 5 unpivot missing `[0]` has an env that leaves `x`
    unbound (1 id). Section 9 "into a scalar" has no env and a missing comma
    (4 ids). Section 9 "into an array" has no env and a row with 3 items
    against 2 (4 ids).
- **Conflict with RFC 0007 (5 ids).** `bag-operators.ion`
  `outerUnionCoerceNullMissing`, `outerIntersectCoerceNullMissing` (both
  modes) and `outerExceptCoerceNullMissing` (strict mode) expect `<<null>>`
  or a failure for a NULL or MISSING OUTER operand. The `eval-equiv` classes
  of RFC 0007 make such an operand the empty bag in both modes, and the
  evaluator follows RFC 0007.
- **Known gap (2 ids).** Section 5 "unpivot non-missing" `[0]#coerce` and
  `[1]#coerce` expect `SELECT * FROM UNPIVOT x AS v AT n` to include the AT
  variable. `SELECT *` lists FROM AS variables only (bead `partiql-kgh`).

### Grouping and aggregates

M4c evaluates GROUP BY, GROUP AS, GROUP ALL, HAVING, the SQL aggregates
(COUNT, SUM, AVG, MIN, MAX, ANY, SOME, EVERY) and the COLL_ functions. Every
assertion of `coll-aggregate-function.ion`, `select/sql-aggregate.ion` and
`ion/query/group-by/group-by.ion` passes. In `query/group-by/group-by.ion`
726 assertions pass, and in the extended `group-by.ion` 50 pass. The
grouping cases that needed CAST pass since M4d2.

M4c adds 30 failing ids in five groups:

- **Corpus defects (8 ids).**
  - `query/group-by/group-by.ion` "group by with group as
    (sales_report.fiscal_year)" (line 637) and "group by with group as and
    where fiscal_year >= DATE literal" (line 753): the expected member
    tuples of `g` leave out `created_date`, `last_modified_time` and
    `last_read_time`, which the `sales_report` rows of the env hold
    (partiql-tests #165 added those attributes and did not update these
    outputs) (4 ids).
  - `query/group-by/group-by.ion` "max and min last_read_time grouped by
    fiscal_year" (line 1076) expects 2002-06-09 as the 2002 minimum; the
    rows hold 2002-05-13, 2002-06-09 and 2002-07-23 (2 ids).
  - `spec-tests.ion` section 11 "windowing simplified with grouping" (line
    818) reads `v.timestamp` from the GROUP AS members, which are tuples
    `{l: row}` (spec section 11.1), and its expected jump (0.4) does not
    satisfy its own `WHERE r.co > 2*orderedReadings[p-1].co` (2 ids).
  (`group-by.ion` line 1026, "max and min of rep grouped by fiscal_year",
  does not parse; it is counted with the M4b1 corpus defects above.)
- **Integer AVG (4 ids).** The `eval-equiv/spec-tests.ion` class
  `aliases_from_select_clause` (line 534) expects `AVG` of integers to be an
  integer. The rest of the corpus (`sql-aggregate.ion`,
  `coll-aggregate-function.ion`, `group-by.ion`) expects a decimal, and the
  evaluator follows the majority.
- **Undefined name in a struct key (2 ids).** `spec-tests.ion` section 11
  "coll_count without group by" is `COLL_COUNT([5, {a:2, b:3}])`. A struct
  key is an expression, so `a` is an undefined variable; this is the same
  class as "data type mismatch in logical expression" above.
- **Extended: Kotlin behaviour of absent keys (12 ids).** The extended
  `group-by.ion` `SELECT *` cases "GROUP BY MISSING AS groupExp" and
  "... AS someMissing" (line 463) and the four `products_sparse` cases with
  `supplierId_missings` and `supplierId_mixed` keep a MISSING key as MISSING,
  so `SELECT *` leaves the key out, and expect `p.supplierId_missings` on a
  row without that attribute to succeed in strict mode. Spec section 11.1
  turns a MISSING key into NULL, and a path to an absent attribute fails in
  strict mode, so the evaluator gives `{'groupExp': NULL}` and a `TypeError`.
  The same cases in the main `group-by.ion` follow the spec and pass.
- **Extended: a GROUP BY or GROUP AS name in FROM or WHERE (4 ids).** The
  four "binding referenced in FROM clause - Extended" and "... WHERE clause
  - Extended" cases (line 183) expect permissive mode to succeed with an
  unbound global name (`non_included_sales_report`). With no FROM variable in
  scope an undefined name is a `DataError` (see "Undefined variable"
  above). The same cases in the main `group-by.ion` expect the failure and
  pass.

### Built-in functions

M4d1 evaluates the built-in scalar functions CHAR_LENGTH (CHARACTER_LENGTH),
OCTET_LENGTH, BIT_LENGTH, UPPER, LOWER, TRIM, SUBSTRING, POSITION, OVERLAY,
TEXT_REPLACE, ABS, MOD, SIZE, CARDINALITY, EXISTS, TUPLEUNION and the RFC 0104
map functions MAP_GET, MAP_CONTAINS_KEY, MAP_KEYS, MAP_VALUES and
MAP_ENTRIES. Map keys now match by value within a type family, also for
`m[k]` (`MAP { 1.0: 'one' }[1]` is `'one'`). Every assertion of
`char_length.ion`, `octet_length.ion`, `bit_length.ion`, `lower.ion`,
`trim.ion`, `substring.ion`, `position.ion`, `overlay.ion`, `abs.ion`,
`ion/abs.ion`, `mod.ion`, `ion/exists.ion` and the extended `size.ion` and
`text_replace.ion` passes. M4d2 (CAST) made the map cases that needed CAST
applicable.

M4d1 adds 8 failing ids in three groups, and the 2 ids of "Map key match
across numeric types" (M4b1) now pass:

- **Undefined name in a struct key (4 ids).** `exists.ion` "exists valid
  cases" with `exists({a: 1})` and `exists({a: null})` write an Ion struct as
  PartiQL. A struct key is an expression, so `a` is an undefined variable,
  as in "coll_count without group by" (M4c).
- **Unicode version (2 ids).** `upper.ion` "upper valid cases{Latin
  Extended-B and IPA Extensions}" expects U+019B (LATIN SMALL LETTER LAMBDA
  WITH STROKE) to stay unchanged. Unicode 16.0 gave it the uppercase U+A7DC,
  and the evaluator uses the Unicode 18.0 case mappings
  (`moonbit-community/unicode-data`). The other 286 UPPER and 288 LOWER
  assertions pass.
- **DATE against Ion timestamp (2 ids).** `map.ion` "map_keys with date keys"
  (line 850): see "DATE against Ion timestamp" above.

The groups add up to 116 ids (41 from M4b1: 6 + 3 + 1 + 6 + 14 + 4 + 4 + 2 +
1; 24 from M4b2: 17 + 5 + 2; 30 from M4c: 8 + 4 + 2 + 12 + 4; 8 from
M4d1: 4 + 2 + 2; 1 from M4d2, see "CAST"; and 12 from M4d3, see "Datetime
functions").

### Ambiguous lookups

A regular identifier ignores ASCII case; a double-quoted identifier matches
exactly. A name matching different spellings in the winning scope frame is a
`DataError` in both modes. Lowering detects variable ambiguity even over an
empty source; evaluation checks globals. In a FROM source, globals precede
earlier FROM variables, so local ambiguity is checked at evaluation only if
no global matches. WITH bindings precede globals, and `@name` selects only a
local variable. Inner frames shadow outer frames,
exact repeated LET names keep the later binding, and exact repeated globals
keep the first binding. ORDER BY output names remain a fallback to variables
inside a non-bare sort key.

Every matching tuple field counts, including exact repeats. Strict mode raises
`TypeError` for repeated matches; permissive mode returns the first match.
The rule applies to explicit paths, named subscripts and implicit attributes,
and to both tuples and Ion structs. Implicit lookup uses the first variable
whose tuple has a match. The literal `[{repeated:1, repeated:2}]` fails because
its keys are references to an undefined variable. Its failure does not test
repeated fields; the Ion literal `` `[{repeated:1, repeated:2}]` `` reaches that
lookup.

### CAST

M4d2 evaluates `CAST` to every type of the grammar except `SEXP` and
`ARRAY<T>` (`Unsupported`). The specification defines only two cases
(`CAST(MISSING AS INTEGER)` and `CAST('1' AS INTEGER)`), so the rules come
from SQL, then the corpus, then partiql-lang-kotlin:

- **Failure classes.** A cast that is not defined for the source kind, or
  text that is not a valid literal of the target, is a type error (MISSING
  in permissive mode). A value out of the range of the target, or the text
  of a number or datetime longer than `CHAR(n)`/`VARCHAR(n)`, is a data error
  in both modes. `CAST(x AS NULL)` and `CAST(x AS MISSING)` are static errors.
- **Numbers.** Rounding is half to even. Text is read as an SQL numeric
  literal (with `0x`, `0o`, `0b` and `_` separators, SQL:2023), so
  `CAST('1.5' AS INT)` is 2. A number with an exponent stays exact, as a
  PartiQL number literal does (`1e3` is a DECIMAL), so every target rounds
  once and the text of a decimal reads back without loss. BOOL and numbers convert both ways (the corpus
  needs BOOL to integers; SQL has neither): zero is FALSE, NaN is a type
  error. A bare `DECIMAL` keeps the scale of the value (38 digits);
  `DECIMAL(p)` has scale 0. A float casts to DECIMAL as the decimal of its
  shortest text, and to an integer by its exact binary value (so
  `` CAST(`-9223372036854775808e0` AS BIGINT) `` fits). `REAL` rounds once
  from the exact value.
- **Text.** BOOL is `TRUE`/`FALSE`; a decimal keeps its scale (scientific
  form outside the range of `DECIMAL(38)`); a float is in SQL form (`1.5E0`;
  `nan`, `+inf`, `-inf`); a datetime or an interval is an SQL `<literal>`, as
  SQL 6.13 requires ("the shortest character string that conforms to the
  definition of `<literal>`"): `DATE '2007-10-10'`, `TIME '12:00:00.5'`,
  `INTERVAL '0 00:00:05' DAY TO SECOND`. An interval value keeps only its
  class, so its literal names the whole class (YEAR TO MONTH or DAY TO
  SECOND). Most engines and partiql-lang-kotlin print the bare string; no
  corpus test covers it. Text casts to a datetime or interval as such a
  literal (read with its own qualifier, then cast to the target) or, since
  SQL:1999, as a bare string under the target's fields, so the text of every
  datetime and interval reads back. `CHAR(n)` pads with spaces; character
  text is cut to `n` code points.
- **LOBs.** STRING to CLOB is UTF-8; CLOB to STRING decodes UTF-8; CLOB and
  BLOB convert to each other; no LOB converts to a number, BOOL or datetime
  (as `ion/primitives/cast.ion` requires).
- **Datetimes.** `evaluate` takes a session time zone (default UTC) and
  follows the SQL rules for WITH and WITHOUT TIME ZONE. A bare TIME or
  TIMESTAMP keeps the precision of the value; `TIME(p)` and `TIMESTAMP(p)`
  round half up with carry. TIME to TIMESTAMP is `Unsupported` (it needs
  CURRENT_DATE).
- **Intervals.** An interval is cut to the last field of the qualifier; a
  leading field that is too long is a data error. An exact number casts to
  a one-field interval; an interval to a number is `Unsupported` (the value
  does not keep its field).
- **Maps (RFC 0104).** A tuple casts to `MAP<K, V>` with a text key type;
  the last duplicate field wins and MISSING values are dropped. A map
  re-casts its keys and values. A MAP literal whose keys (or values) all
  cast to one type has that map type.
- **Lowering.** `t[CAST(e AS STRING)]` names a field (spec, paths), and the
  implied name of `CAST(e AS T)` is that of `e` (GROUP BY keys, SELECT
  items).

One CAST assertion fails: `cast.ion` "cast to int invalid values" with
`'2e10'` (`cast('2e10' as INT)`) expects MISSING in permissive mode. In SQL `'2e10'` is
a valid approximate literal whose value is out of the range of INT, a data
error in both modes, as the extended `int.ion` overflow cases expect (the
evaluator reads it as the exact number 20000000000). The evaluator follows
SQL.

### Datetime functions

M4d3 evaluates EXTRACT, DATE_ADD, DATE_DIFF, OVERLAPS, TO_STRING and
TO_TIMESTAMP. The specification does not define them, so SQL decides EXTRACT
(SQL-92 6.6) and OVERLAPS (8.11), and the corpus and the partiql-lang-kotlin
documentation decide the others:

- **EXTRACT** gives an integer, except SECOND: a decimal whose scale is the
  precision of the value. TIMEZONE_HOUR and TIMEZONE_MINUTE carry the sign of
  the offset. A field the source does not have is a type error. Interval
  values keep only their class (year-month or day-time), so EXTRACT reads the
  normalized fields: `EXTRACT(HOUR FROM INTERVAL '27' HOUR)` is 3, where SQL
  gives 27.
- **DATE_ADD** adds whole units of the field and keeps the type, precision
  and offset of the value. A field the type lacks (`DATE_ADD(hour, 1, DATE
  ...)`) is a type error (SQL 6.14).
- **DATE_DIFF** counts whole elapsed units, toward zero, from day to second,
  and complete calendar months for month and year (as Java `ChronoUnit`).
- **OVERLAPS** is SQL-92 8.11 in three-valued logic, on lists or bags of two
  elements.
- **TO_STRING and TO_TIMESTAMP** use the PartiQL format patterns (`y`, `yy`,
  `yyyy`, `M`..`MMMMM`, `d`, `H`, `h`, `a`, `m`, `s`, `S`, `n`, `X`, `x`,
  quoted text), with English names. A bad pattern, or text that does not
  match, is a data error in both modes.
- **Values without an offset** are in the session time zone (`evaluate`
  `zone~`, default UTC) for DATE_DIFF and OVERLAPS.
- **Arithmetic** follows SQL since M4d3: a year-month step onto a day the
  month lacks (`DATE '2025-01-31' + INTERVAL '1' MONTH`) is a data error, not
  the month end, and every datetime result must be in years 0001-9999.

12 datetime assertions fail:

- `extract.ion:495` (2 assertions) uses `TIME (2) WITH TIME ZONE '01:23:45.678'`
  without an offset, which `time.ion` and `timestamp.ion` require to fail.
- Five `date_add_invalid` tests in the extended corpus (10 assertions) expect
  a WITH TIME ZONE input to lose its offset and the years 19998 and -1 to be
  valid, as partiql-lang-kotlin v1 does.

### Session clock

CURRENT_DATE, CURRENT_TIME [(p)], CURRENT_TIMESTAMP [(p)] and UTCNOW() read a
clock that the caller injects (`evaluate` `clock~`, a `Clock` returning a
`moonbitlang/x/time` `ZonedDateTime`); the library never reads the wall
clock, and the `partiql` CLI is the composition root that passes the real one.
All references in one statement see one instant (SQL-92 6.8), read at most
once and only when the statement uses a clock function. CURRENT_TIME and
CURRENT_TIMESTAMP carry the session offset (default precisions 0 and 6;
fractions are cut); UTCNOW() is at offset 0 with precision 6, as in
partiql-lang-kotlin v1. CAST of TIME to TIMESTAMP takes the date from
CURRENT_DATE (SQL-92 6.10). Without a clock these are data errors. The
`partiql query` uses the session time zone UTC unless `--time-zone +HH:MM`
(or `-HH:MM`) sets it. The corpus has no test of them.

Every corpus value passes `codec`, including the `$map` (M1b MAP) and
`$graph` (M1b graph) values.

All 172 `.ion` files decode with `moonrockz/ion` 0.2.0 (5,611 test cases).

## Later corpora

- The tree-sitter grammar test corpus in
  [partiql/partiql-grammar](https://github.com/partiql/partiql-grammar), as an
  extra syntax corpus (M2).
