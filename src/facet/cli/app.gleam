//// CLI orchestration: parse the argument list, resolve configuration,
//// dispatch to the client, render the result and return a process exit code
//// (0 success, 1 error). Pure — nothing here halts the VM — so tests can
//// drive `main` directly. Only the real entry point in `facet_cli` halts.

import facet/cli/args
import facet/cli/commands
import facet/cli/render
import facet/cli/types
import facet/config
import gleam/io
import gleam/option.{None, Some}

/// Run the CLI over a raw argument list (program name excluded) and return
/// the exit code.
pub fn main(cli_args: List(String)) -> Int {
  case args.parse(cli_args) {
    Error(message) -> fail(message)
    Ok(invocation) ->
      case invocation.command {
        types.Help -> {
          io.println(render.usage())
          0
        }
        command -> run_command(invocation, command)
      }
  }
}

fn run_command(
  invocation: types.ParsedInvocation,
  command: types.Command,
) -> Int {
  case resolve_config(invocation) {
    Error(error) -> fail(config.error_to_string(error))
    Ok(config) ->
      case commands.run(config, command) {
        Error(error) -> fail(types.error_to_string(error))
        Ok(output) -> {
          let rendered = case invocation.json {
            True -> render.render_json(output)
            False -> render.render(output)
          }
          io.print(rendered)
          0
        }
      }
  }
}

/// `--url`/`--token` win over the environment; otherwise fall back to the
/// `FACET_URL`/`FACET_TOKEN` variables (or the local sidecar default URL).
fn resolve_config(
  invocation: types.ParsedInvocation,
) -> Result(config.Config, config.ClientError) {
  let base_url = case invocation.url {
    Some(url) -> url
    None -> option.unwrap(config.get_env("FACET_URL"), config.default_base_url)
  }
  let token = case invocation.token {
    Some(token) -> Some(token)
    None -> config.get_env("FACET_TOKEN")
  }
  config.resolve_with(base_url, token)
}

fn fail(message: String) -> Int {
  io.println_error("facet: " <> message)
  1
}
