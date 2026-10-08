// The moonrockz/partiql-eval module: the PartiQL evaluator.

name = "moonrockz/partiql-eval"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/moonrockz/partiql"

license = "Apache-2.0"

keywords = [ "partiql", "sql", "query", "evaluator" ]

description = "A PartiQL evaluator for MoonBit."

source = "src"

// Derived Eq/Debug methods on public types (krueger pattern).

warnings = "-implicit_impl_as_method"

import {
  "moonrockz/partiql-value@0.1.0",
  "moonrockz/partiql-syntax@0.1.0",
  "moonrockz/ion@0.2.0",
  "moonrockz/expect@0.6.0",
}
