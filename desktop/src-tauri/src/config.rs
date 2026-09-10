use serde::Deserialize;
use std::path::PathBuf;

/// Configuration compiled into the binary from `sidecar.toml`.
///
/// The TOML is embedded with `include_str!` so the same values are used in
/// development and in a bundled `.app` / `.exe` without shipping a separate
/// resource file.
const SIDECAR_TOML: &str = include_str!("../sidecar.toml");

#[derive(Debug, Deserialize, Clone)]
pub struct SidecarConfig {
    pub sidecar: SidecarSection,
    pub health: HealthSection,
}

#[derive(Debug, Deserialize, Clone)]
pub struct SidecarSection {
    /// Binary name without platform suffix (e.g. `crystalline`).
    pub binary_name: String,
    /// Preferred port. A random free port is used if this one is taken.
    pub default_port: u16,
    /// Default database path, relative to the user's home directory.
    pub default_db_path: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct HealthSection {
    pub path: String,
    pub timeout_secs: u64,
    pub poll_interval_ms: u64,
}

impl SidecarConfig {
    /// Parse the embedded `sidecar.toml`.
    pub fn load() -> anyhow::Result<Self> {
        toml::from_str(SIDECAR_TOML)
            .map_err(|e| anyhow::anyhow!("Failed to parse embedded sidecar.toml: {}", e))
    }

    /// Preferred port after applying the `CRYSTALLINE_PORT` override.
    pub fn preferred_port(&self) -> u16 {
        std::env::var("CRYSTALLINE_PORT")
            .ok()
            .and_then(|value| value.parse().ok())
            .unwrap_or(self.sidecar.default_port)
    }

    /// Database path, honouring the `CRYSTALLINE_DB` override.
    ///
    /// `dirs::data_dir()` maps to the platform-correct location and, on macOS,
    /// is exactly `~/Library/Application Support` — the path required by the
    /// sidecar spec.
    pub fn db_path(&self) -> PathBuf {
        if let Ok(path) = std::env::var("CRYSTALLINE_DB") {
            return expand_tilde(&path);
        }

        if let Some(data_dir) = dirs::data_dir() {
            return data_dir.join("Facet").join("crystalline.db");
        }

        expand_tilde(&self.sidecar.default_db_path)
    }
}

/// Resolve a path that may start with `~/` against the user's home directory.
pub fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = dirs::home_dir() {
            return home.join(rest);
        }
    }
    PathBuf::from(path)
}

/// Create the database parent directory if it does not exist yet.
pub fn ensure_parent_dir(path: &std::path::Path) -> anyhow::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    Ok(())
}
