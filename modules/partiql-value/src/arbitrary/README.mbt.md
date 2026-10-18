# Property tests for PartiQL values

Import `moonrockz/partiql-value/arbitrary` alongside
`moonbitlang/core/quickcheck` in your test imports. The package supplies
`ArbValue`, `ArbIon` and `ArbTimestamp` wrappers with `Arbitrary` and `Shrink`
implementations. Read the generated value through each wrapper's `value` field.

```mbt nocheck
///|
import {
  "moonrockz/partiql-value/arbitrary",
  "moonrockz/partiql-value/ion" @partiql_ion,
  "moonbitlang/core/quickcheck",
} for "test"
```

This property checks the public codec on generated values, including bags,
maps, graphs, absent values and boxed Ion:

```mbt check
///|
test "generated values round trip through PartiQL Ion" {
  @quickcheck.check(
    (generated : @arbitrary.ArbValue) => {
      @partiql_ion.from_ion(@partiql_ion.to_ion(generated.value)) ==
      generated.value
    },
    count=25,
  )
}
```

For explicit control over generation, pass a size budget and a seeded
`moonbitlang/core/quickcheck/splitmix.RandomState` to `gen_value` or a
specialized generator. `gen_value` halves its size budget when descending into
containers; nonpositive sizes produce leaves. `ArbValue` caps that budget at
eight. Random state advances on every generated sample.

`gen_ion` chooses from representative parsed Ion examples and currently ignores
its size argument. Its samples include annotations, symbols, typed nulls,
containers and special numbers. `ArbIon` shrinks by dropping annotations and
selecting container children. `ArbTimestamp` shrinks toward midnight UTC on
2000-01-01.

`has_nested_absent` detects NULL or MISSING inside a value. It is useful for
restricting properties whose equivalence rules differ for nested absence.
Generate edge cases deliberately as well; random samples do not prove coverage
of every representation.
