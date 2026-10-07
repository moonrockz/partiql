///|
/// A small PartiQL expression text of depth at most 3: literals of every
/// kind (NULL, MISSING and wrong types included) under the M4a operators.
struct ExprText {
  text : String
} derive(Debug)

///|
let expr_atoms : Array[String] = [
  "0", "1", "-1", "2", "7", "9223372036854775807", "'a'", "'b%'", "''", "TRUE", "FALSE",
  "NULL", "MISSING", "1.5", "2e0", "`2.5e0`", "[1, 2]", "<<1>>", "{'a': 1}", "DATE '2020-01-02'",
  "x",
]

///|
let expr_binary : Array[String] = [
  "+", "-", "*", "/", "%", "||", "=", "<>", "<", "<=", ">", ">=", "AND", "OR", "IN",
  "LIKE", "NOT IN", "NOT LIKE",
]

///|
fn pick(rs : @splitmix.RandomState, n : Int) -> Int {
  rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn gen_expr(rs : @splitmix.RandomState, depth : Int) -> String {
  if depth == 0 || pick(rs, 4) == 0 {
    return expr_atoms[pick(rs, expr_atoms.length())]
  }
  match pick(rs, 8) {
    0 => "(NOT \{gen_expr(rs, depth - 1)})"
    1 => "(-\{gen_expr(rs, depth - 1)})"
    2 => {
      let tests = ["IS NULL", "IS MISSING", "IS NOT NULL", "IS NOT MISSING"]
      "(\{gen_expr(rs, depth - 1)} \{tests[pick(rs, tests.length())]})"
    }
    3 => {
      let neg = if pick(rs, 2) == 0 { "" } else { "NOT " }
      "(\{gen_expr(rs, depth - 1)} \{neg}BETWEEN \{gen_expr(rs, depth - 1)} AND \{gen_expr(rs, depth - 1)})"
    }
    _ => {
      let op = expr_binary[pick(rs, expr_binary.length())]
      "(\{gen_expr(rs, depth - 1)} \{op} \{gen_expr(rs, depth - 1)})"
    }
  }
}

///|
impl @quickcheck.Arbitrary for ExprText with fn arbitrary(_size, rs) {
  { text: gen_expr(rs, 3), }
}

///|
impl @quickcheck.Shrink for ExprText

///|
/// The result of evaluating: a value, a TypeError (`Err(false)`) or any other
/// failure (`Err(true)`).
fn outcome(source : String, mode : @eval.Mode) -> Result[@value.Value, Bool] {
  try ev(source, mode~) catch {
    @eval.EvalError::TypeError(..) => Err(false)
    _ => Err(true)
  } noraise {
    v => Ok(v)
  }
}

///|
test "law: modes agree" {
  @quickcheck.check(
    (t : ExprText) => {
      let strict = outcome(t.text, Strict)
      let lax = outcome(t.text, Permissive)
      match strict {
        Ok(_) => lax == strict
        // a strict TypeError: permissive gives MISSING at the failing operation
        Err(false) => true
        // a DataError (or anything else) fails in both modes
        Err(true) => lax == Err(true)
      }
    },
    count=2000,
  )
}

///|
test "law: evaluation is deterministic and never aborts" {
  @quickcheck.check(
    (t : ExprText) => outcome(t.text, Permissive) == outcome(t.text, Permissive),
    count=500,
  )
}

///|
let logic_inputs : Array[String] = ["TRUE", "FALSE", "NULL", "MISSING"]

///|
/// Evaluates a logic expression; it must give a value, so a failure shows as a
/// String that no table entry equals.
fn logic(source : String) -> @value.Value {
  ev(source) catch {
    e => String("error: \{@debug.to_string(e)}")
  }
}

///|
/// Kleene truth tables, with MISSING acting as NULL inside AND, OR and NOT.
fn kleene(v : String) -> Bool? {
  match v {
    "TRUE" => Some(true)
    "FALSE" => Some(false)
    _ => None
  }
}

///|
fn expect_bool(b : Bool?) -> @value.Value {
  match b {
    Some(x) => Bool(x)
    None => Null
  }
}

///|
test "law: AND, OR and NOT follow the three-valued tables" {
  @expect.expect_all(soft => {
    for a in logic_inputs {
      soft
      .expect(logic("NOT \{a}"))
      .to_equal(expect_bool(kleene(a).map(x => !x)))
      for b in logic_inputs {
        let (x, y) = (kleene(a), kleene(b))
        let and_expected = match (x, y) {
          (Some(false), _) | (_, Some(false)) => Some(false)
          (Some(true), Some(true)) => Some(true)
          _ => None
        }
        let or_expected = match (x, y) {
          (Some(true), _) | (_, Some(true)) => Some(true)
          (Some(false), Some(false)) => Some(false)
          _ => None
        }
        soft.expect(logic("\{a} AND \{b}")).to_equal(expect_bool(and_expected))
        soft.expect(logic("\{a} OR \{b}")).to_equal(expect_bool(or_expected))
      }
    }
  })
}

///|
test "law: AND and OR commute, associate and obey De Morgan" {
  @expect.expect_all(soft => {
    for a in logic_inputs {
      for b in logic_inputs {
        soft.expect(logic("\{a} AND \{b}")).to_equal(logic("\{b} AND \{a}"))
        soft.expect(logic("\{a} OR \{b}")).to_equal(logic("\{b} OR \{a}"))
        soft
        .expect(logic("NOT (\{a} AND \{b})"))
        .to_equal(logic("(NOT \{a}) OR (NOT \{b})"))
        soft
        .expect(logic("NOT (\{a} OR \{b})"))
        .to_equal(logic("(NOT \{a}) AND (NOT \{b})"))
        for c in logic_inputs {
          soft
          .expect(logic("(\{a} AND \{b}) AND \{c}"))
          .to_equal(logic("\{a} AND (\{b} AND \{c})"))
          soft
          .expect(logic("(\{a} OR \{b}) OR \{c}"))
          .to_equal(logic("\{a} OR (\{b} OR \{c})"))
        }
      }
    }
  })
}

///|
/// A number literal of a random kind: an Int64 (near the limits too), a
/// decimal, or a float from an Ion literal. Decimals and floats are multiples
/// of 0.25 in a small range, so sums and differences are exact.
struct NumText {
  text : String
} derive(Debug)

///|
fn int_text(n : Int64) -> String {
  if n < 0L {
    "(-\{(0L - n).to_string()})"
  } else {
    n.to_string()
  }
}

///|
fn gen_num(rs : @splitmix.RandomState) -> String {
  let small = (pick(rs, 2001) - 1000).to_int64()
  match pick(rs, 5) {
    0 => int_text(small)
    1 => {
      let hi = rs.next_uint().to_int64() << 32
      let lo = rs.next_uint().to_int64()
      let n = hi | lo
      // Int64 minimum has no literal
      int_text(if n == -9223372036854775808L { 0L } else { n })
    }
    2 => {
      let k = pick(rs, 6).to_int64()
      int_text(
        if pick(rs, 2) == 0 {
          9223372036854775807L - k
        } else {
          k - 9223372036854775807L
        },
      )
    }
    3 => "(\{(small / 4L).to_string()}.\{["0", "25", "5", "75"][pick(rs, 4)]})"
    _ =>
      "`\{(small / 4L).to_string()}.\{["0", "25", "5", "75"][pick(rs, 4)]}e0`"
  }
}

///|
impl @quickcheck.Arbitrary for NumText with fn arbitrary(_size, rs) {
  { text: gen_num(rs), }
}

///|
impl @quickcheck.Shrink for NumText

///|
test "law: a + b - b = a and a * 1 = a" {
  @quickcheck.check(
    (p : (NumText, NumText)) => {
      let (a, b) = p
      // Float arithmetic is exact only below 2^53: no claim for a float next
      // to a large integer.
      let is_float = (t : NumText) => t.text.has_suffix("e0`")
      let is_large = (t : NumText) => t.text.length() > 9
      if (is_float(a) && is_large(b)) || (is_float(b) && is_large(a)) {
        return true
      }
      let va = ev(a.text)
      // a DataError (overflow) makes no claim
      let plus = try ev("\{a.text} + \{b.text} - \{b.text}") catch {
        _ => return true
      } noraise {
        v => v
      }
      let times = ev("\{a.text} * 1")
      @value.compare(plus, va, nulls=NullsFirst) == 0 &&
      @value.compare(times, va, nulls=NullsFirst) == 0
    },
    count=2000,
  )
}

///|
test "law: < agrees with the value order on numbers and strings" {
  @quickcheck.check(
    (p : (NumText, NumText)) => {
      let (a, b) = p
      let (va, vb) = (ev(a.text), ev(b.text))
      let c = @value.compare(va, vb, nulls=NullsFirst)
      ev("\{a.text} < \{b.text}") == Bool(c < 0) &&
      ev("\{a.text} <= \{b.text}") == Bool(c <= 0) &&
      ev("\{a.text} > \{b.text}") == Bool(c > 0) &&
      ev("\{a.text} >= \{b.text}") == Bool(c >= 0)
    },
    count=2000,
  )
  @quickcheck.check(
    (p : (String, String)) => {
      let (a, b) = p
      // escape for a PartiQL string literal
      let lit = (s : String) => "'" + s.replace_all(old="'", new="''") + "'"
      let c = @value.compare(String(a), String(b), nulls=NullsFirst)
      ev("\{lit(a)} < \{lit(b)}") == Bool(c < 0) &&
      ev("\{lit(a)} = \{lit(b)}") == Bool(a == b)
    },
    count=500,
  )
}

///|
test "law: = agrees with sql_equals when neither side is absent" {
  @quickcheck.check(
    (p : (ExprText, ExprText)) => {
      let (a, b) = p
      match (outcome(a.text, Permissive), outcome(b.text, Permissive)) {
        (Ok(va), Ok(vb)) =>
          if va.is_absent() || vb.is_absent() {
            true
          } else {
            outcome("(\{a.text}) = (\{b.text})", Permissive) ==
            Ok(@value.sql_equals(va, vb))
          }
        _ => true
      }
    },
    count=2000,
  )
}
