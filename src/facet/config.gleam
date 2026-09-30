//// Facet client configuration.
////
//// The base URL, optional bearer token and project scope are resolved from the
//// environment (`FACET_URL`, `FACET_TOKEN`, `FACET_PROJECT`) and — for the
//// project — the persisted config file written by `facet init`. The CLI adds a
//// `--project` flag that outranks all of these; see `resolve_project_for`.
//// When no URL is configured the client targets the local Crystalline sidecar
//// at `http://localhost:4920`.
////
//// `validate` performs a live check against the server's `/health` endpoint.

import facet/ffi
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri

/// Default Crystalline base URL used when `FACET_URL` is not set.
pub const default_base_url = "http://localhost:4920"

/// Header carrying the project id or slug that scopes a request.
pub const project_header = "x-crystalline-project"

/// Environment variable holding the project scope (overrides the config file).
pub const project_env = "FACET_PROJECT"

/// Environment variable overriding the config file path (used by tests).
pub const config_path_env = "FACET_CONFIG"

/// Resolved client configuration. `project` is the scope sent as
/// `X-Crystalline-Project`; `None` leaves the engine on its `default` project.
pub type Config {
  Config(base_url: String, token: Option(String), project: Option(String))
}

/// Every failure mode of the Facet HTTP client.
pub type ClientError {
  /// The transport failed before an HTTP response was received.
  NetworkError(message: String)
  /// The server returned a non-2xx response.
  HttpError(status_code: Int, body: String)
  /// The response body could not be decoded into the expected type.
  DecodeError(message: String)
  /// The client configuration (URL/token) is missing or malformed.
  ConfigError(message: String)
}

/// The configuration used when no environment variables are set.
pub fn default_config() -> Config {
  Config(base_url: default_base_url, token: None, project: None)
}

/// Resolve configuration from `FACET_URL`, `FACET_TOKEN` and `FACET_PROJECT`.
///
/// - A valid `FACET_URL` yields `Ok(Config)`.
/// - With none of the variables set, yields `Ok(default_config())`.
/// - A malformed URL yields `Error(ConfigError)`.
///
/// The persisted project (`facet init`) is *not* consulted here; the CLI adds
/// it through `resolve_project_for` so the flag > env > file order stays in one
/// place.
pub fn resolve() -> Result(Config, ClientError) {
  let base_url = case get_env("FACET_URL") {
    Some(url) -> url
    None -> default_base_url
  }
  let token = get_env("FACET_TOKEN")
  let project = get_env(project_env)
  resolve_with(base_url, token, project)
}

/// Like `resolve`, accepting explicit URL, token and project values. Explicit
/// values are used as given (the CLI passes `--url` / `--token` / `--project`
/// here).
pub fn resolve_with(
  base_url: String,
  token: Option(String),
  project: Option(String),
) -> Result(Config, ClientError) {
  case valid_url(base_url) {
    True -> Ok(Config(base_url:, token:, project:))
    False -> Error(ConfigError("invalid base URL: " <> base_url))
  }
}

/// Alias for `resolve`, for callers that prefer the explicit name.
pub fn resolve_from_env() -> Result(Config, ClientError) {
  resolve()
}

// ─── Persisted project (config file) ────────────────────────────────────────

/// The persisted client config. Today it only remembers the project scope
/// written by `facet init`; unknown keys are ignored so the file can grow.
pub type ConfigFile {
  ConfigFile(project: Option(String))
}

/// The config file path: `FACET_CONFIG` wins, then
/// `$XDG_CONFIG_HOME/facet/config.json`, then `$HOME/.config/facet/config.json`,
/// falling back to `.facet.json` in the working directory.
pub fn config_file_path() -> String {
  case get_env(config_path_env) {
    Some(path) -> path
    None ->
      case get_env("XDG_CONFIG_HOME") {
        Some(dir) -> dir <> "/facet/config.json"
        None ->
          case get_env("HOME") {
            Some(home) -> home <> "/.config/facet/config.json"
            None -> ".facet.json"
          }
      }
  }
}

/// Read the persisted config, tolerating a missing or malformed file (both
/// mean "no persisted project" rather than a hard failure).
pub fn read_config_file() -> ConfigFile {
  case ffi.read_file(config_file_path()) {
    Error(_) -> ConfigFile(project: None)
    Ok(content) -> decode_config_file(content)
  }
}

fn decode_config_file(content: String) -> ConfigFile {
  case json.parse(content, config_file_decoder()) {
    Ok(config_file) -> config_file
    Error(_) -> ConfigFile(project: None)
  }
}

fn config_file_decoder() -> decode.Decoder(ConfigFile) {
  use project <- decode.optional_field(
    "project",
    None,
    decode.optional(decode.string),
  )
  decode.success(ConfigFile(project: project))
}

/// Resolve the project scope, most specific source first:
/// `--project` flag > `FACET_PROJECT` > config file > absent.
pub fn resolve_project_for(
  flag: Option(String),
  env: Option(String),
  config_file: ConfigFile,
) -> Option(String) {
  case flag, env {
    Some(project), _ -> Some(project)
    None, Some(project) -> Some(project)
    None, None -> config_file.project
  }
}

/// Persist `project` (an id or slug) as the client's default scope, creating
/// the parent directory if needed. `facet init` is the only caller.
pub fn save_project(project: String) -> Result(Nil, ClientError) {
  let path = config_file_path()
  let body = json.to_string(json.object([#("project", json.string(project))]))
  case ffi.make_dir(dirname(path)) {
    Error(message) ->
      Error(ConfigError("cannot create config directory: " <> message))
    Ok(_) ->
      case ffi.write_file(path, body) {
        Ok(_) -> Ok(Nil)
        Error(message) ->
          Error(ConfigError("cannot write " <> path <> ": " <> message))
      }
  }
}

fn dirname(path: String) -> String {
  case string.split(path, "/") {
    [_, ..] -> {
      let segments = string.split(path, "/")
      let #(parent, _) = list.split(segments, list.length(segments) - 1)
      case string.join(parent, "/") {
        "" -> "/"
        parent -> parent
      }
    }
    _ -> "."
  }
}

/// Validate a configuration by requesting `/health` from the server.
///
/// Returns the configuration unchanged on a 2xx response.
pub fn validate(config: Config) -> Result(Config, ClientError) {
  case request.to(health_url(config.base_url)) {
    Error(_) -> Error(ConfigError("invalid base URL: " <> config.base_url))
    Ok(req) -> {
      let req =
        req
        |> request.set_method(http.Get)
        |> request.set_header("accept", "application/json")
        |> add_auth(config)

      case httpc.send(req) {
        Error(error) -> Error(NetworkError(httpc_error_to_string(error)))
        Ok(response) ->
          case response.status >= 200 && response.status < 300 {
            True -> Ok(config)
            False -> Error(HttpError(response.status, response.body))
          }
      }
    }
  }
}

/// True when the string is a well-formed `http(s)` URL with a host.
pub fn valid_url(url: String) -> Bool {
  case uri.parse(url) {
    Ok(parsed) ->
      case parsed.scheme, parsed.host {
        Some(scheme), Some(host) -> {
          let is_http = scheme == "http" || scheme == "https"
          is_http && host != ""
        }
        _, _ -> False
      }
    Error(_) -> False
  }
}

/// Human-readable rendering of a `ClientError`.
pub fn error_to_string(error: ClientError) -> String {
  case error {
    NetworkError(message) -> "network error: " <> message
    HttpError(status_code, body) ->
      "HTTP " <> string.inspect(status_code) <> ": " <> body
    DecodeError(message) -> "decode error: " <> message
    ConfigError(message) -> "config error: " <> message
  }
}

/// Read an environment variable, treating an empty value as unset.
pub fn get_env(name: String) -> Option(String) {
  case ffi.getenv(name) {
    "" -> None
    value -> Some(value)
  }
}

// ─── Internals ──────────────────────────────────────────────────────────────

fn health_url(base_url: String) -> String {
  trim_trailing_slashes(base_url) <> "/health"
}

fn trim_trailing_slashes(url: String) -> String {
  case string.ends_with(url, "/") {
    True -> string.drop_end(url, 1)
    False -> url
  }
}

fn add_auth(
  req: request.Request(String),
  config: Config,
) -> request.Request(String) {
  case config.token {
    Some(token) -> request.set_header(req, "authorization", "Bearer " <> token)
    None -> req
  }
}

fn httpc_error_to_string(error: httpc.HttpError) -> String {
  case error {
    httpc.InvalidUtf8Response -> "invalid UTF-8 response"
    httpc.FailedToConnect(_, _) -> "failed to connect to the server"
    httpc.ResponseTimeout -> "request timed out"
  }
}
