// The PartiQL conformance harness. Never published: it runs the
// partiql-tests suite (git submodule `partiql-tests`) against the
// workspace modules.

name = "moonrockz/partiql-conformance"

version = "0.1.0"

repository = "https://github.com/moonrockz/partiql"

license = "Apache-2.0"

description = "Conformance harness for moonrockz/partiql. Not published."

source = "src"

// Derived Eq/Debug methods on public types (krueger pattern).

warnings = "-implicit_impl_as_method"

import {
  "moonrockz/partiql-value@0.1.0",
  "moonrockz/partiql-syntax@0.1.0",
  "moonrockz/ion@0.2.0",
  "moonbitlang/x@0.5.5",
  "moonrockz/expect@0.6.0",
}
