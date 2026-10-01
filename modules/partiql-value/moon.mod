// The moonrockz/partiql-value module: the PartiQL data model and its
// PartiQL-encoded Ion representation.

name = "moonrockz/partiql-value"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/moonrockz/partiql"

license = "Apache-2.0"

keywords = [ "partiql", "sql", "query", "ion", "data-model" ]

description = "The PartiQL data model for MoonBit, with a PartiQL-encoded Ion codec."

source = "src"

// Derived Eq/Debug methods on public types (krueger pattern).

warnings = "-implicit_impl_as_method"

import {
  "moonrockz/ion@0.2.0",
  "moonrockz/expect@0.6.0",
}
