# YAML fixture provenance

`../upstream_test.mbt` contains verbatim input strings and expected JSON values
from https://github.com/yaml/yaml-test-suite, data-branch commit
`6ad3d2c62885d82fc349026c136ef560838fdf3d`. The upstream case IDs and descriptions
are retained in test names and comments. [MIT license](LICENSE).

Regenerate with a checkout of that exact data revision:

```sh
python3 .github/scripts/generate_yaml_fixtures.py /path/to/yaml-test-suite
moon fmt
```

The cases cover block/flow containers, multiline folding and chomping, explicit
tags, Unicode anchors, empty nodes/streams and malformed syntax. Supported
cases must decode to the expected values. Unsupported tags must produce
`Unsupported`; invalid syntax must produce `Syntax`. Additional codec tests
cover BOMs, duplicate names, directives, exact numbers, aliases, diagnostics and
resource limits. This selected subset is separate from the PartiQL conformance
ratchet and makes no full YAML compliance claim.
