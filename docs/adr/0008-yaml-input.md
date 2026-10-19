# 0008. YAML input with exact values and bounded aliases

Status: Accepted

YAML is an input codec in `partiql-value/yaml`, shared by the binding API and
CLI. We use YAML 1.2 Core resolution. Finite float spellings become exact Ion
Decimal values, preserving scale and signed zero; only infinities and NaN
become Float. Binary64 conversion would lose configuration values before a
query could inspect them. Mappings become ordered tuples with unique string
keys. Non-string keys and duplicate decoded names are errors.

Readers return one Value per document. Empty streams contain no values; empty
documents contain Null. Bindings require exactly one tuple. The CLI's existing
zero/one/many data-binding rule applies to YAML streams. `--each` expands a
single List, otherwise it iterates whole documents. All input is decoded before
evaluation. Ion remains the default input and output format.

Aliases copy content into independent trees because Value lists expose mutable
storage. Depth, expanded nodes and decoded scalar bytes have fixed budgets;
metadata for each completed anchor permits rejecting an expansion before
copying it. Cycles and forward references fail. Anchor and directive state is
local to each document. See the [codec contract](../../modules/partiql-value/README.mbt.md#yaml-input)
for exact accounting and supported encodings and tags.

The event parser is vendored from `moonbit-community/yaml` 0.0.8 at
`64fb8d91d4c4f69c647373e6d1bae9840f370b15`, under its MIT license, in
`partiql-value/internal/yaml_parser`. Its public push callback cannot raise or
stop parsing; using its materialized Yaml/JSON representation would also lose
our numeric and duplicate-key semantics. The vendored parser exposes pull
events, limits token work and scalar-buffer growth, and fixes version checking,
BOM handling, directive accumulation, empty indentless sequence entries and verbatim tag scanning. Its API is an
implementation detail, not a supported codec API. Replacing it with a released
upstream parser requires retaining these guarantees and fixture results.

This is input-only support. There is no YAML writer, YAML 1.1 resolution,
implicit merge expansion, arbitrary-tag construction, UTF-16/32 decoder, or
comment/style preservation. A selected, pinned YAML test suite subset verifies
supported decoding and distinguishes unsupported mappings from invalid syntax;
it does not claim full YAML compliance or affect the PartiQL conformance ratchet.
