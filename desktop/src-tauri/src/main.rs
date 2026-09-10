// Prevents an additional console window on Windows in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod config;
mod sidecar;

use std::sync::Mutex;
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, RunEvent};

/// Event emitted whenever the connection status changes.
const STATUS_EVENT: &str = "facet://status";

/// Payload describing the current connection to Crystalline.
#[derive(Debug, Clone, Serialize)]
pub struct Status {
    /// `starting` | `ready` | `error`
    pub state: String,
    /// `embedded` | `remote`
    pub mode: String,
    /// Resolved base URL, known once a port is picked or in remote mode.
    pub base_url: Option<String>,
    /// Port of the local sidecar (embedded mode only).
    pub port: Option<u16>,
    /// Version reported by Crystalline's `/health`, when available.
    pub version: Option<String>,
    /// Human-readable error shown as a banner in the UI.
    pub error: Option<String>,
}

impl Status {
    fn starting(mode: &str, base_url: Option<String>, port: Option<u16>) -> Self {
        Self {
            state: "starting".into(),
            mode: mode.into(),
            base_url,
            port,
            version: None,
            error: None,
        }
    }

    fn ready(
        mode: &str,
        base_url: Option<String>,
        port: Option<u16>,
        version: Option<String>,
    ) -> Self {
        Self {
            state: "ready".into(),
            mode: mode.into(),
            base_url,
            port,
            version,
            error: None,
        }
    }

    fn error(
        mode: &str,
        base_url: Option<String>,
        port: Option<u16>,
        error: String,
    ) -> Self {
        Self {
            state: "error".into(),
            mode: mode.into(),
            base_url,
            port,
            version: None,
            error: Some(error),
        }
    }
}

/// State shared between the bootstrap task and the Tauri commands.
struct AppState {
    status: Mutex<Status>,
    sidecar: Mutex<Option<sidecar::SidecarHandle>>,
}

/// Tauri command: the frontend asks for the resolved configuration once, then
/// keeps it up to date through `facet://status` events.
#[tauri::command]
fn get_config(state: tauri::State<AppState>) -> Status {
    state.status.lock().unwrap().clone()
}

/// Store and broadcast a new status.
fn publish(app: &AppHandle, status: Status) {
    {
        let state = app.state::<AppState>();
        *state.status.lock().unwrap() = status.clone();
    }
    if let Err(e) = app.emit(STATUS_EVENT, &status) {
        log::warn!("Failed to emit status event: {}", e);
    }
}

/// Resolve the sidecar mode and bring it up, publishing status as it progresses.
async fn bootstrap(app: AppHandle) {
    let cfg = match config::SidecarConfig::load() {
        Ok(cfg) => cfg,
        Err(e) => {
            publish(&app, Status::error("embedded", None, None, e.to_string()));
            return;
        }
    };

    match sidecar::determine_mode() {
        sidecar::Mode::Remote(url) => {
            log::info!("Remote mode: {}", url);
            publish(
                &app,
                Status::starting("remote", Some(url.clone()), None),
            );

            match sidecar::verify_remote(&url).await {
                Ok(report) => publish(
                    &app,
                    Status::ready("remote", Some(url), None, report.version),
                ),
                Err(e) => publish(
                    &app,
                    Status::error("remote", Some(url), None, e.to_string()),
                ),
            }
        }
        sidecar::Mode::Embedded => {
            log::info!("Embedded mode: spawning sidecar");
            publish(&app, Status::starting("embedded", None, None));

            let handle = match sidecar::spawn(&cfg) {
                Ok(handle) => handle,
                Err(e) => {
                    log::error!("Failed to spawn sidecar: {}", e);
                    publish(&app, Status::error("embedded", None, None, e.to_string()));
                    return;
                }
            };

            let port = handle.port();
            let base = sidecar::base_url(port);
            log::info!("Sidecar listening on {}", base);
            publish(
                &app,
                Status::starting("embedded", Some(base.clone()), Some(port)),
            );

            // Keep the handle so it can be terminated on exit.
            {
                let state = app.state::<AppState>();
                *state.sidecar.lock().unwrap() = Some(handle);
            }

            let timeout = Duration::from_secs(cfg.health.timeout_secs);
            let interval = Duration::from_millis(cfg.health.poll_interval_ms);

            match sidecar::wait_for_health(&base, &cfg.health.path, timeout, interval).await {
                Ok(report) => {
                    log::info!("Sidecar healthy (version: {:?})", report.version);
                    publish(
                        &app,
                        Status::ready("embedded", Some(base), Some(port), report.version),
                    );
                }
                Err(e) => {
                    log::error!("Sidecar health check failed: {}", e);
                    // Tear down the unhealthy process instead of leaking it.
                    if let Some(mut handle) = app.state::<AppState>().sidecar.lock().unwrap().take() {
                        let _ = handle.stop();
                    }
                    publish(
                        &app,
                        Status::error(
                            "embedded",
                            Some(base),
                            Some(port),
                            format!("Crystalline failed to start: {}", e),
                        ),
                    );
                }
            }
        }
    }
}

/// Route SIGTERM/SIGINT through the normal exit path.
///
/// The default signal behaviour kills the process immediately, which would
/// skip `RunEvent::Exit` and orphan the spawned Crystalline process. Asking
/// the app to exit gracefully runs the event loop's shutdown, where the
/// sidecar is stopped first.
fn install_signal_handlers(handle: AppHandle) {
    std::thread::spawn(move || {
        let mut signals = match signal_hook::iterator::Signals::new([
            signal_hook::consts::signal::SIGINT,
            signal_hook::consts::signal::SIGTERM,
        ]) {
            Ok(signals) => signals,
            Err(e) => {
                log::warn!("Failed to install signal handlers: {}", e);
                return;
            }
        };
        for signal in signals.forever() {
            log::info!("Received signal {}, exiting gracefully", signal);
            handle.exit(0);
        }
    });
}

/// Terminate the sidecar if one is running. Safe to call more than once.
fn shutdown(app: &AppHandle) {
    if let Some(mut handle) = app
        .try_state::<AppState>()
        .and_then(|state| state.sidecar.lock().unwrap().take())
    {
        if let Err(e) = handle.stop() {
            log::error!("Failed to stop sidecar during shutdown: {}", e);
        }
    }
}

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    tauri::Builder::default()
        .manage(AppState {
            status: Mutex::new(Status::starting("embedded", None, None)),
            sidecar: Mutex::new(None),
        })
        .invoke_handler(tauri::generate_handler![get_config])
        .setup(|app| {
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                bootstrap(handle).await;
            });
            install_signal_handlers(app.handle().clone());
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building Facet")
        .run(|app, event| {
            if matches!(event, RunEvent::ExitRequested { .. } | RunEvent::Exit) {
                log::info!("Shutting down — terminating sidecar if running");
                shutdown(app);
            }
        });
}
