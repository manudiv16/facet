//// Tests for configuration resolution and validation.

import facet/config
import facet/ffi
import gleam/int
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
  let assert Ok(resolved) =
    config.resolve_with("https://api.example.com", None, None)
  assert resolved.base_url == "https://api.example.com"

  let assert Error(config.ConfigError(_)) =
    config.resolve_with("nonsense", None, None)
}

pub fn default_config_uses_local_sidecar_port_test() {
  assert config.default_config()
    == config.Config(
      base_url: "http://localhost:4920",
      token: None,
      project: None,
    )
}

// ─── Project scope ──────────────────────────────────────────────────────────

pub fn resolve_reads_the_project_environment_test() {
  set("FACET_PROJECT", "acme")
  let assert Ok(resolved) = config.resolve()
  assert resolved.project == Some("acme")
  unset("FACET_PROJECT")
}

pub fn project_precedence_is_flag_then_env_then_file_test() {
  let file = config.ConfigFile(project: Some("from-file"))
  // flag > env > file
  assert config.resolve_project_for(Some("from-flag"), Some("from-env"), file)
    == Some("from-flag")
  // env > file
  assert config.resolve_project_for(None, Some("from-env"), file)
    == Some("from-env")
  // file > absent
  assert config.resolve_project_for(None, None, file) == Some("from-file")
  assert config.resolve_project_for(
      None,
      None,
      config.ConfigFile(project: None),
    )
    == None
}

pub fn save_project_writes_the_scope_that_read_config_file_returns_test() {
  let path = "/tmp/facet-config-save-" <> int_suffix() <> ".json"
  set("FACET_CONFIG", path)
  assert config.save_project("acme") == Ok(Nil)
  assert config.read_config_file() == config.ConfigFile(project: Some("acme"))
  unset("FACET_CONFIG")
}

pub fn read_config_file_tolerates_missing_and_malformed_files_test() {
  set("FACET_CONFIG", "/tmp/facet-config-missing-" <> int_suffix() <> ".json")
  assert config.read_config_file() == config.ConfigFile(project: None)

  let malformed = "/tmp/facet-config-bad-" <> int_suffix() <> ".json"
  set("FACET_CONFIG", malformed)
  let _ = ffi.write_file(malformed, "not json")
  assert config.read_config_file() == config.ConfigFile(project: None)
  unset("FACET_CONFIG")
}

pub fn config_file_path_prefers_facet_config_then_xdg_test() {
  set("FACET_CONFIG", "/tmp/explicit-config.json")
  assert config.config_file_path() == "/tmp/explicit-config.json"
  unset("FACET_CONFIG")

  set("XDG_CONFIG_HOME", "/tmp/xdg-home")
  assert config.config_file_path() == "/tmp/xdg-home/facet/config.json"
  unset("XDG_CONFIG_HOME")
}

fn int_suffix() -> String {
  // Unique enough to avoid collisions between runs.
  int.to_string(int.random(1_000_000_000))
}

fn set(name: String, value: String) -> Nil {
  let _ = ffi.putenv(name, value)
  Nil
}

fn unset(name: String) -> Nil {
  let _ = ffi.unsetenv(name)
  Nil
}
