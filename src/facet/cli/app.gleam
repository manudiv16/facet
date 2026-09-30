//// CLI orchestration: parse the argument list, resolve configuration,
//// dispatch to the client, render the result and return a process exit code
//// (0 success, 1 error). Pure — nothing here halts the VM — so tests can
//// drive `main` directly. Only the real entry point in `facet_cli` halts.

import facet/cli/args
import facet/cli/commands
import facet/cli/render
import facet/cli/types
import facet/config
import facet/ffi
import gleam/io
import gleam/option.{None, Some}
import gleam/string

/// Run the CLI over a raw argument list (program name excluded) and return
/// the exit code. Standard input is read for `artifact put --content -`.
pub fn main(cli_args: List(String)) -> Int {
  main_with(cli_args, ffi.read_stdin)
}

/// Like `main`, but with stdin injected so tests can exercise
/// `artifact put --content -` without feeding the process.
pub fn main_with(cli_args: List(String), read_stdin: fn() -> String) -> Int {
  case args.parse(cli_args) {
    Error(message) -> fail(message)
    Ok(invocation) ->
      case invocation.command {
        types.Help -> {
          io.println(render.usage())
          0
        }
        command -> run_command(invocation, resolve_stdin(command, read_stdin))
      }
  }
}

/// Replace `--content -` with the text read from stdin before dispatch; every
/// other command passes through untouched.
fn resolve_stdin(
  command: types.Command,
  read_stdin: fn() -> String,
) -> types.Command {
  case command {
    types.ArtifactPut(task_id, logical_name, types.StdinContent) ->
      types.ArtifactPut(
        task_id,
        logical_name,
        types.InlineContent(read_stdin()),
      )
    other -> other
  }
}

fn run_command(
  invocation: types.ParsedInvocation,
  command: types.Command,
) -> Int {
  case resolve_config(invocation) {
    Error(config_error) -> fail(config.error_to_string(config_error))
    Ok(client_config) ->
      case commands.run(client_config, command) {
        Error(error) -> fail(error_message(client_config, error))
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

/// `--url`/`--token`/`--project` win over the environment; otherwise fall back
/// to `FACET_URL`/`FACET_TOKEN`/`FACET_PROJECT` (or the local sidecar default
/// URL), then to the project persisted by `facet init`.
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
  let project =
    config.resolve_project_for(
      invocation.project,
      config.get_env(config.project_env),
      config.read_config_file(),
    )
  config.resolve_with(base_url, token, project)
}

/// A 404 for a configured project means the scope does not exist; say so in
/// the user's terms instead of echoing the engine's raw JSON. Public so the
/// unknown-project message is pinned by a test.
pub fn error_message(
  client_config: config.Config,
  error: types.CliError,
) -> String {
  case client_config.project, error {
    Some(_), types.RequestError(config.HttpError(404, body)) ->
      case string.contains(body, "Unknown project") {
        True ->
          "unknown project: run `facet init <slug>` to create it, or pass --project <id|slug>"
        False -> types.error_to_string(error)
      }
    _, _ -> types.error_to_string(error)
  }
}

fn fail(message: String) -> Int {
  io.println_error("facet: " <> message)
  1
}
