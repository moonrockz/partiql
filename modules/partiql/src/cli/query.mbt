// `partiql query` (spec M4e): evaluates statements against global bindings
// read from Ion, and prints each result as PartiQL-encoded Ion.

///|
fn query_command(m : @argparse.Matches, io : Io, color : Bool) -> Outcome {
  let out = StringBuilder()
  let errors = StringBuilder()
  let inputs = match read_inputs("query", m, io, errors) {
    Ok(inputs) => inputs
    Err(outcome) => return outcome
  }
  let globals : Array[(String, @value.Value)] = []
  if errors.to_string() != "" {
    return finish(out, errors)
  }
  // Every input must parse before any statement runs.
  let scripts : Array[(Input, Array[@syntax.Statement])] = []
  for input in inputs {
    let r = @syntax.parse_script_recovering(input.source)
    for e in r.errors {
      errors.write_string(
        @syntax.render(e, input.source, name=input.name, color~),
      )
    }
    scripts.push((input, r.script.statements))
  }
  if errors.to_string() != "" {
    return finish(out, errors)
  }
  let env = @eval.Bindings::of_pairs(globals)
  let mode : @eval.Mode = if m.flags.get("strict") == Some(true) {
    Strict
  } else {
    Permissive
  }
  let compact = m.flags.get("compact") == Some(true)
  for script in scripts {
    let (input, statements) = script
    for statement in statements {
      let value = @eval.evaluate(statement, env~, mode~) catch {
        e => {
          errors.write_string(eval_error_text(e, input, color))
          return finish(out, errors)
        }
      }
      let ion = @partiql_ion.to_ion(value)
      let text = try {
        if compact {
          @text.write_ion(ion)
        } else {
          @text.write_ion_pretty(ion)
        }
      } catch {
        e => {
          errors.write_string(
            "partiql query: \{input.name}: cannot write the result: \{e.message()}\n",
          )
          return finish(out, errors)
        }
      }
      out.write_string(text + "\n")
    }
  }
  finish(out, errors)
}

///|
/// The rendered diagnostic of an evaluation error in `input` (spec M4e §6).
fn eval_error_text(e : @eval.EvalError, input : Input, color : Bool) -> String {
  let (message, span) = match e {
    TypeError(message~, span~) => ("type error: " + message, span)
    DataError(message~, span~) => ("data error: " + message, span)
    // The message already says "is not supported yet" (plan ruling 2).
    Unsupported(message~, span~) => (message, span)
    Syntax(p) => return @syntax.render(p, input.source, name=input.name, color~)
  }
  @syntax.render_message(message, span, input.source, name=input.name, color~)
}
