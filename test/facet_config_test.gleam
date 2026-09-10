//// Tests for configuration resolution and validation.

import facet/config
import facet/ffi
import gleam/option.{None, Some}

pub fn resolve_defaults_when_unset_test() {
  unset("FACET_URL")
  unset("FACET_TOKEN")
  let assert Ok(resolved) = config.resolve()
  assert resolved.base_url == config.default_base_url
  assert resolved.token == None
}

pub fn resolve_reads_environment_test() {
  set("FACET_URL", "http://example.com:1234")
  set("FACET_TOKEN", "secret-token")
  let assert Ok(resolved) = config.resolve()
  assert resolved.base_url == "http://example.com:1234"
  assert resolved.token == Some("secret-token")
  unset("FACET_URL")
  unset("FACET_TOKEN")
}

pub fn resolve_rejects_malformed_url_test() {
  unset("FACET_TOKEN")
  set("FACET_URL", "not a url")
  let assert Error(config.ConfigError(_)) = config.resolve()
  unset("FACET_URL")
}

pub fn resolve_with_validates_explicit_values_test() {
  let assert Ok(resolved) = config.resolve_with("https://api.example.com", None)
  assert resolved.base_url == "https://api.example.com"

  let assert Error(config.ConfigError(_)) =
    config.resolve_with("nonsense", None)
}

pub fn default_config_uses_local_sidecar_port_test() {
  assert config.default_config()
    == config.Config(base_url: "http://localhost:4920", token: None)
}

fn set(name: String, value: String) -> Nil {
  let _ = ffi.putenv(name, value)
  Nil
}

fn unset(name: String) -> Nil {
  let _ = ffi.unsetenv(name)
  Nil
}
