//// Facet client configuration.
////
//// The base URL and optional bearer token are resolved from the environment
//// (`FACET_URL` / `FACET_TOKEN`). When no URL is configured the client targets
//// the local Crystalline sidecar at `http://localhost:4920`.
////
//// `validate` performs a live check against the server's `/health` endpoint.

import facet/ffi
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri

/// Default Crystalline base URL used when `FACET_URL` is not set.
pub const default_base_url = "http://localhost:4920"

/// Resolved client configuration.
pub type Config {
  Config(base_url: String, token: Option(String))
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
  Config(base_url: default_base_url, token: None)
}

/// Resolve configuration from `FACET_URL` and `FACET_TOKEN`.
///
/// - A valid `FACET_URL` yields `Ok(Config)`.
/// - With neither variable set, yields `Ok(default_config())`.
/// - A malformed URL yields `Error(ConfigError)`.
pub fn resolve() -> Result(Config, ClientError) {
  let base_url = case get_env("FACET_URL") {
    Some(url) -> url
    None -> default_base_url
  }
  let token = get_env("FACET_TOKEN")
  resolve_with(base_url, token)
}

/// Like `resolve`, accepting explicit URL and token values. Explicit values
/// are used as given (the CLI passes `--url` / `--token` here).
pub fn resolve_with(
  base_url: String,
  token: Option(String),
) -> Result(Config, ClientError) {
  case valid_url(base_url) {
    True -> Ok(Config(base_url:, token:))
    False -> Error(ConfigError("invalid base URL: " <> base_url))
  }
}

/// Alias for `resolve`, for callers that prefer the explicit name.
pub fn resolve_from_env() -> Result(Config, ClientError) {
  resolve()
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
