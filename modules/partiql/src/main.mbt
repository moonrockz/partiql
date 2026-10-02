///|
async fn main {
  let args = @env.args()[1:]
  // `run` is synchronous, so stdin is read before it when the command needs
  // it.
  let stdin : Result[String, Error] = if @cli.reads_stdin(args) {
    Ok(@stdio.stdin.read_all().text()) catch {
      e => Err(e)
    }
  } else {
    Err(Failure("stdin was not read"))
  }
  let io : @cli.Io = {
    read_file: path => {
      @fs.read_file_to_string(path) catch {
        IOError(message) => raise Failure(message)
      }
    },
    write_file: (path, text) => {
      @fs.write_string_to_file(path, text) catch {
        IOError(message) => raise Failure(message)
      }
    },
    read_stdin: () => {
      match stdin {
        Ok(text) => text
        Err(e) => raise e
      }
    },
    color_default: stderr_is_terminal() && @env.get_env_var("NO_COLOR") is None,
  }
  let outcome = @cli.run(args, io~)
  if outcome.stdout != "" {
    println(outcome.stdout.trim_end(chars="\n"))
  }
  if outcome.stderr != "" {
    eprintln(outcome.stderr.trim_end(chars="\n"))
  }
  if outcome.status != 0 {
    @sys.exit(outcome.status)
  }
}
