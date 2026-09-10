use anyhow::{anyhow, Result};
use std::net::TcpListener;
use std::path::PathBuf;
use std::process::{Child, Command};
use std::time::{Duration, Instant};

use crate::config::{self, SidecarConfig};

/// How the app talks to Crystalline.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Mode {
    /// Spawn and manage a local Crystalline process.
    Embedded,
    /// Talk to a remote Crystalline instance given by `FACET_URL`.
    Remote(String),
}

/// Owns the spawned Crystalline process.
pub struct SidecarHandle {
    child: Child,
    port: u16,
    stopped: bool,
}

impl SidecarHandle {
    pub fn port(&self) -> u16 {
        self.port
    }

    /// Process id. Used by the lifecycle tests to assert the process is
    /// running and later reaped; kept public for diagnostics.
    #[allow(dead_code)]
    pub fn pid(&self) -> u32 {
        self.child.id()
    }

    /// Terminate the sidecar: SIGTERM first, then force kill after a grace period.
    pub fn stop(&mut self) -> Result<()> {
        if self.stopped {
            return Ok(());
        }
        self.stopped = true;

        // Already gone?
        if self.child.try_wait()?.is_some() {
            return Ok(());
        }

        log::info!("Stopping sidecar (pid {})", self.child.id());
        terminate(&mut self.child);

        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            if self.child.try_wait()?.is_some() {
                log::info!("Sidecar exited gracefully");
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(100));
        }

        log::warn!("Sidecar did not exit within grace period — killing it");
        let _ = self.child.kill();
        let _ = self.child.wait();
        Ok(())
    }
}

impl Drop for SidecarHandle {
    fn drop(&mut self) {
        let _ = self.stop();
    }
}

/// Send a graceful termination signal where the platform supports it.
#[cfg(unix)]
fn terminate(child: &mut Child) {
    // SAFETY: `kill` only takes a pid and a signal number.
    unsafe {
        libc::kill(child.id() as libc::pid_t, libc::SIGTERM);
    }
}

#[cfg(not(unix))]
fn terminate(child: &mut Child) {
    // Windows has no SIGTERM equivalent; `kill` is the closest available.
    let _ = child.kill();
}

/// Metadata reported by the sidecar's health endpoint.
#[derive(Debug, Clone, Default)]
pub struct HealthReport {
    pub version: Option<String>,
}

/// Determine the base URL of the sidecar for a given port.
pub fn base_url(port: u16) -> String {
    format!("http://127.0.0.1:{}", port)
}

/// Read `FACET_URL` to decide between remote and embedded mode.
pub fn determine_mode() -> Mode {
    match std::env::var("FACET_URL") {
        Ok(url) if !url.trim().is_empty() => Mode::Remote(url.trim().trim_end_matches('/').to_string()),
        _ => Mode::Embedded,
    }
}

/// Pick the preferred port when free, otherwise ask the OS for a random one.
pub fn find_free_port(preferred: u16) -> u16 {
    if preferred != 0 && is_port_free(preferred) {
        return preferred;
    }

    let listener =
        TcpListener::bind("127.0.0.1:0").expect("failed to bind an ephemeral port");
    listener
        .local_addr()
        .expect("failed to read ephemeral port")
        .port()
}

fn is_port_free(port: u16) -> bool {
    TcpListener::bind(("127.0.0.1", port)).is_ok()
}

/// Spawn the Crystalline sidecar with `PORT` and `CRYSTALLINE_DB` set.
pub fn spawn(config: &SidecarConfig) -> Result<SidecarHandle> {
    let name = &config.sidecar.binary_name;
    let path = resolve_binary(name).ok_or_else(|| {
        anyhow!(
            "Crystalline sidecar binary `{}{}` was not found. Run `scripts/build.sh` \
             (or `scripts/dev-sidecar.sh`) before starting the app.",
            name,
            std::env::consts::EXE_SUFFIX
        )
    })?;

    let port = find_free_port(config.preferred_port());
    let db_path = config.db_path();
    config::ensure_parent_dir(&db_path)?;

    log::info!(
        "Spawning sidecar {} on port {} (db: {})",
        path.display(),
        port,
        db_path.display()
    );

    let mut command = Command::new(&path);
    command
        .env("PORT", port.to_string())
        .env("CRYSTALLINE_DB", db_path.to_string_lossy().to_string());

    // On Windows, avoid flashing a console window for the sidecar.
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        command.creation_flags(CREATE_NO_WINDOW);
    }

    let child = command
        .spawn()
        .map_err(|e| anyhow!("failed to spawn sidecar {}: {}", path.display(), e))?;

    log::info!("Sidecar started with pid {}", child.id());

    Ok(SidecarHandle {
        child,
        port,
        stopped: false,
    })
}

/// Locate the platform-suffixed sidecar binary.
///
/// Tauri copies `binaries/<name>-<target-triple>[.exe]` next to the main
/// executable (both in `target/{debug,release}` and inside the bundle), so the
/// executable directory is checked first. The raw `binaries/` directory is a
/// fallback for running the binary via plain `cargo run`.
pub fn resolve_binary(name: &str) -> Option<PathBuf> {
    let file_name = format!("{}{}", name, std::env::consts::EXE_SUFFIX);

    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            let candidate = dir.join(&file_name);
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }

    let suffixed = format!(
        "{}-{}{}",
        name,
        target_triple(),
        std::env::consts::EXE_SUFFIX
    );
    let candidate = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("binaries")
        .join(suffixed);
    candidate.is_file().then_some(candidate)
}

/// Rust target triple used to suffix the sidecar binary.
pub fn target_triple() -> String {
    if let Some(triple) = option_env!("TAURI_ENV_TARGET_TRIPLE") {
        return triple.to_string();
    }

    // Fallback for builds outside of the Tauri tooling.
    let arch = std::env::consts::ARCH;
    match std::env::consts::OS {
        "macos" => format!("{}-apple-darwin", arch),
        "linux" => format!("{}-unknown-linux-gnu", arch),
        "windows" => format!("{}-pc-windows-msvc", arch),
        other => format!("{}-unknown-{}", arch, other),
    }
}

/// Poll `<base_url><health_path>` until it answers 2xx or the timeout expires.
pub async fn wait_for_health(
    base_url: &str,
    health_path: &str,
    timeout: Duration,
    poll_interval: Duration,
) -> Result<HealthReport> {
    let url = format!("{}{}", base_url.trim_end_matches('/'), health_path);
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .build()?;

    let start = Instant::now();
    let mut last_error = String::from("no response yet");

    loop {
        if start.elapsed() >= timeout {
            return Err(anyhow!(
                "timed out after {}s waiting for {} ({})",
                timeout.as_secs(),
                url,
                last_error
            ));
        }

        match client.get(&url).send().await {
            Ok(resp) if resp.status().is_success() => {
                let version = resp
                    .json::<serde_json::Value>()
                    .await
                    .ok()
                    .and_then(|value| extract_version(&value));
                return Ok(HealthReport { version });
            }
            Ok(resp) => last_error = format!("HTTP {}", resp.status()),
            Err(e) => last_error = e.to_string(),
        }

        tokio::time::sleep(poll_interval).await;
    }
}

/// Best-effort extraction of a version string from a health payload.
fn extract_version(value: &serde_json::Value) -> Option<String> {
    value
        .get("version")
        .and_then(|v| v.as_str())
        .or_else(|| {
            value
                .get("data")
                .and_then(|data| data.get("version"))
                .and_then(|v| v.as_str())
        })
        .map(str::to_string)
}

/// Check that a remote instance is reachable, returning its reported version.
pub async fn verify_remote(url: &str) -> Result<HealthReport> {
    let base = url.trim_end_matches('/');
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()?;

    let resp = client
        .get(format!("{}/health", base))
        .send()
        .await
        .map_err(|e| anyhow!("remote instance unreachable at {}: {}", base, e))?;

    if !resp.status().is_success() {
        return Err(anyhow!(
            "remote health check at {}/health returned HTTP {}",
            base,
            resp.status()
        ));
    }

    let version = resp
        .json::<serde_json::Value>()
        .await
        .ok()
        .and_then(|value| extract_version(&value));

    Ok(HealthReport { version })
}

/// Convenience for tests: is the given process still running?
#[cfg(test)]
pub fn is_running(pid: u32) -> bool {
    #[cfg(unix)]
    {
        unsafe { libc::kill(pid as libc::pid_t, 0) == 0 }
    }
    #[cfg(not(unix))]
    {
        let _ = pid;
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn free_port_is_bindable() {
        let port = find_free_port(0);
        assert!(port > 0, "expected an ephemeral port, got {port}");
        assert!(TcpListener::bind(("127.0.0.1", port)).is_ok());
    }

    #[test]
    fn preferred_port_is_used_when_free() {
        // Find an actual free port first, then ask for it explicitly.
        let free = find_free_port(0);
        assert_eq!(find_free_port(free), free);
    }

    #[test]
    fn target_triple_is_not_empty() {
        assert!(!target_triple().trim().is_empty());
    }

    /// End-to-end lifecycle test against the dev stub, when it is installed.
    ///
    /// Run with `scripts/dev-sidecar.sh` first. Skipped otherwise so CI does not
    /// depend on Node or a Crystalline build.
    #[tokio::test]
    async fn spawns_health_checks_and_stops_cleanly() {
        let Some(_) = resolve_binary("crystalline") else {
            eprintln!("skipping: dev stub sidecar not installed");
            return;
        };

        let db_path = std::env::temp_dir().join(format!("facet-test-{}.db", std::process::id()));
        std::env::set_var("CRYSTALLINE_DB", &db_path);

        let cfg = crate::config::SidecarConfig::load().expect("config");
        let mut handle = spawn(&cfg).expect("spawn sidecar");
        let port = handle.port();
        let pid = handle.pid();
        assert!(is_running(pid));

        let report = wait_for_health(
            &base_url(port),
            &cfg.health.path,
            Duration::from_secs(15),
            Duration::from_millis(200),
        )
        .await
        .expect("health");
        assert!(report.version.is_some());

        handle.stop().expect("stop");
        assert!(!is_running(pid), "sidecar process was orphaned");
        let _ = std::fs::remove_file(&db_path);
    }
}
