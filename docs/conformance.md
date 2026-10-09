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
| `codec` | each `env` and each `EvaluationSuccess` `output` | `v = from_ion(x)` succeeds; `from_ion(to_ion(v)) == v` (structural identity); and `to_ion` is a fixpoint after one round trip |
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
- `eval-equiv` cases are not applicable until M4b2.

Two cases (`eval/primitives/map.ion`, lines 850 and 1194) expect a DATE
written as a plain Ion timestamp. Line 850 needs `map_keys` and is not
applicable. Line 1194 ("unpivot map with date keys") runs since M4b1 and
fails in both modes, because the comparison does not treat a DATE and a
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
(expression evaluation) and M4b1 (query evaluation core):

| Check | Passed | Total | N/A |
|---|---|---|---|
| `syntax` | 425 | 672 | 247 |
| `eval-parse` | 4982 | 4985 | 0 |
| `codec` | 6822 | 6822 | 0 |
| `ion-roundtrip` | 39 | 39 | 0 |
| `print-roundtrip` | 5310 | 5313 | 3 |
| `pretty-roundtrip` | 5310 | 5313 | 3 |
| `recovery` | 5410 | 5410 | 0 |
| `eval` | 3719 | 9960 | 6195 |

The 3 `eval-parse` failures are corpus defects (bead `partiql-zhj.9`):

- `eval/query/group-by/group-by.ion` "max and min of rep grouped by
  fiscal_year": `SELECT max(rep), min(rep)) FROM ...` has a stray `)`.
- `eval/primitives/functions/cardinality.ion` (the case with `()`): an empty
  `()` is not PartiQL (the Kotlin grammar has no such expression, and
  `fail/syntax` requires `SELECT () FROM data` to fail).
- `eval-equiv/spec-tests.ion` "equiv coercion of a SELECT subquery into a
  scalar" `[1]`: a struct with a missing comma.

### The `eval` check

Of 9960 assertions, 3719 pass and 6195 are not applicable: they need ORDER BY,
LIMIT, set operations, PIVOT, WITH, grouping, functions, CAST, graph MATCH or
`?`, which later parts of M4 add. 46 fail. M4b1 raised the passes from 2952
to 3719 (767 more) and cut the not-applicable set by 781. To list the
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
- **Map key match across numeric types (2 ids).** "access map with
  cross-type cast integer to decimal key" is `MAP { 1.0: 'one', 2.0: 'two' }[1]`
  and expects `'one'`. The evaluator does not match map keys across numeric
  types yet.
- **DATE against Ion timestamp (2 ids).** "unpivot map with date keys" gives
  DATE keys, and the corpus writes them as Ion timestamps. The comparison of
  the harness does not treat a DATE and a midnight UTC TIMESTAMP as equal.
- **Ambiguous names in strict mode (3 ids).** "repeated field on Ion struct is
  ambiguous" (2 ids) and "path expression with ambiguous table alias
  (lowercase, unquoted)" expect a failure when two names differ only in case.
  The evaluator takes the first match.
- **`a.*.*.*.*` in strict mode (1 id).** `pathUnpivotWildCardOverStructMultiple`
  expects a failure. Every `.*` step applies to a tuple, so the evaluator
  succeeds; the corpus expectation is taken as an artifact.

The groups add up to 46 ids (6 + 3 + 1 + 6 + 14 + 4 + 4 + 2 + 2 + 3 + 1).

Every corpus value passes `codec`, including the `$map` (M1b MAP) and
`$graph` (M1b graph) values.

All 172 `.ion` files decode with `moonrockz/ion` 0.2.0 (5,611 test cases).

## Later corpora

- The tree-sitter grammar test corpus in
  [partiql/partiql-grammar](https://github.com/partiql/partiql-grammar), as an
  extra syntax corpus (M2).
