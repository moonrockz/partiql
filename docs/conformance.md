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

`ParseError::Unsupported` and `CodecError::Unsupported` always count as
failures.

The `codec` check does not require the encoded Ion to equal the input Ion:
the reference runners decode Ion symbols as strings and accept legacy
`$date`/`$time` forms, so the encoder writes strings and the new canonical
forms (see ADR 0005). Evaluation results are not checked until an evaluator exists.

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

At commit `2ef0ce2`, after M1 (data model):

| Check | Passed | Total | N/A |
|---|---|---|---|
| `syntax` | 0 | 672 | 247 |
| `eval-parse` | 0 | 4985 | 0 |
| `codec` | 6545 | 6822 | 0 |
| `ion-roundtrip` | 39 | 39 | 0 |

The 277 `codec` failures are the `$map` (169) and `$graph` (108) values, which
M1b adds.

All 172 `.ion` files decode with `moonrockz/ion` 0.2.0 (5,611 test cases).

## Later corpora

- The tree-sitter grammar test corpus in
  [partiql/partiql-grammar](https://github.com/partiql/partiql-grammar), as an
  extra syntax corpus (M2).
