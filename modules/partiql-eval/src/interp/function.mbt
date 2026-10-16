///|
/// Runs a built-in on evaluated arguments. Each `ops` function applies the
/// shared argument rule (spec M4d1 §4.3).
fn call(
  f : @plan.Function,
  args : Array[@value.Value],
  ctx : Ctx,
) -> @value.Value raise @ops.OpFailure {
  match f {
    CharLength => @ops.char_length(args)
    OctetLength => @ops.octet_length(args)
    BitLength => @ops.bit_length(args)
    Size => @ops.size(args)
    Cardinality => @ops.cardinality(args)
    Exists => @ops.exists(args)
    TupleUnion => @ops.tuple_union(args)
    MapGet => @ops.map_get(args)
    MapContainsKey => @ops.map_contains_key(args)
    MapKeys => @ops.map_keys(args)
    MapValues => @ops.map_values(args)
    MapEntries => @ops.map_entries(args)
    Abs => @ops.abs(args)
    Mod => @ops.modulo(args)
    Trim(spec) => @ops.trim(spec, args)
    Substring => @ops.substring(args)
    Position => @ops.position(args)
    Overlay => @ops.overlay(args)
    TextReplace => @ops.text_replace(args)
    Upper => @ops.upper(args)
    Lower => @ops.lower(args)
    Extract(field) => @ops.extract(field, args)
    DateAdd(field) => @ops.date_add(field, args)
    DateDiff(field) => @ops.date_diff(field, args, zone=ctx.zone)
    Overlaps => @ops.overlaps(args, zone=ctx.zone)
    ToString => @ops.datetime_to_string(args)
    ToTimestamp => @ops.text_to_timestamp(args)
    CurrentDate => Date(clock_now(ctx, f.name(), ctx.zone, 0).date)
    CurrentTime(p) => Time(clock_now(ctx, f.name(), ctx.zone, p).time)
    CurrentTimestamp(p) => Timestamp(clock_now(ctx, f.name(), ctx.zone, p))
    UtcNow => Timestamp(clock_now(ctx, f.name(), @ops.ZoneOffset::utc(), 6))
  }
}

///|
/// The statement instant seen at `zone` with `precision` fraction digits.
fn clock_now(
  ctx : Ctx,
  name : String,
  zone : @ops.ZoneOffset,
  precision : Int32,
) -> @value.Timestamp raise @ops.OpFailure {
  let (seconds, nanos) = ctx.statement_instant(name)
  @ops.clock_timestamp(seconds, nanos, zone, precision)
}
