# 0004. Conformance ratchet baseline

Date: 2026-10-01

Status: Accepted

## Context

The implementation starts with almost no passing conformance tests. The
`moonrockz/ion` repository uses a skip list: each test that is known to fail
is listed with a reason. For partiql-tests, a skip list would start with about
4,500 entries and shrink slowly. It would be noise.

## Decision

Keep a baseline of **passing** test ids per check
(`modules/partiql-conformance/baseline/<check>.txt`). A baseline id that fails
is a regression and fails the test. A passing id that is not in the baseline
is a new pass. `mise run conformance:ratchet` rewrites the baseline. CI runs
the ratchet and fails when the baseline changes, so every new pass is
recorded in the same pull request.

## Consequences

- The baseline only grows, except when a pin bump changes the suite.
- A change that makes tests pass must also commit the baseline.
- The baseline files show the current conformance status in the repository.
