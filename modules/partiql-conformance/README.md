# moonrockz/partiql-conformance

The conformance harness for this repository. It runs the
[partiql-tests](https://github.com/partiql/partiql-tests) suite (git submodule
`partiql-tests`) against the workspace modules and compares the result with
the ratchet baseline in `baseline/`. This module is never published. See
`docs/conformance.md` in the repository.

## Run the suite

From the repository root:

```sh
mise run setup
mise run test:conformance
```

The harness requires the pinned submodule and runs on native and JavaScript.
It reads test data from disk. It checks syntax, parsing of evaluation cases,
PartiQL Ion codecs, boxed Ion round trips, canonical and pretty printing,
error recovery and evaluation in permissive and strict modes.

Each check prints a machine-readable `CONFORMANCE` JSON line. A passing id
recorded in `baseline/<check>.txt` must keep passing. New passes require a
baseline update; never remove ids to hide a regression.

```sh
# Show evaluation failures and reasons.
PARTIQL_CONFORMANCE_SHOW=eval mise run test:conformance

# After an implementation change introduces new passes, regenerate the baseline.
mise run conformance:ratchet
```

Commit a generated baseline with the code change that made the cases pass.
`Unsupported` is never a successful expected error. For evaluation it counts
as not applicable; for parsing and codecs it counts as failure.

## Add or update coverage

Unit and property tests belong in the library packages. This harness consumes
the upstream corpus and compares against the shared baseline. Its local tests
also cover corpus loading, ids, report generation and regression detection.
The corpus submodule is read-only during ordinary implementation work.

See [the full conformance guide](../../docs/conformance.md) for the exact pass
conditions, encodings, corpus pin update procedure and current results.
