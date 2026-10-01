# moonrockz/partiql-value

The PartiQL data model for MoonBit.

Status: M0. Only the absent values `NULL` and `MISSING` exist. M1 adds
scalars, tuples, lists and bags. See `docs/roadmap.md` in the repository.

```moonbit
let v = @value.Value::Missing
v.is_absent() // true
```
