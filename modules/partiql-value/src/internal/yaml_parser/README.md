# Vendored YAML event parser

Source: https://github.com/moonbit-community/yaml.mbt
Version: 0.0.8, commit `64fb8d91d4c4f69c647373e6d1bae9840f370b15`.
License: [MIT](LICENSE), including the yaml-rust and yaml-rust2 notices.

Only scanner/event-parser sources are retained. The Yaml loader and emitter
are not used. This package is internal to the YAML codec.

Local changes:

- Pull events through `next_token`, with per-document anchor reset.
- Bound scanner tokens, nesting and UTF-8 scalar-buffer growth before allocation;
  reserve copied alias payload against the same stream budget.
- Reject YAML versions other than 1.2 with a typed error.
- Accumulate all tag directives and detect duplicate handles.
- Preserve empty entries in indentless block sequences as Null.
- Consume characters in verbatim tag scanning, avoiding the upstream loop.
- Recognize BOMs at line starts and expose markers for view-relative diagnostics.

Regressions live in `../../yaml/`. Keep this provenance and license when updating
these sources. ADR 0008 explains why the registry package cannot yet replace them.
