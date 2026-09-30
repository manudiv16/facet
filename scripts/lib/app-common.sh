#!/usr/bin/env bash
#
# Shared helpers for the Facet.app launchers and the bundle smoke check.
#
# Sourced — never executed — by `scripts/run-app-stub.sh`,
# `scripts/run-app-live.sh` and `scripts/smoke-app.sh`. It only defines
# functions; each caller sets `set -euo pipefail` itself.

# Repository root, derived from this file's location (scripts/lib/../..).
FACET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Bundle produced by `scripts/build.sh` / `cargo tauri build` on macOS.
FACET_DEFAULT_BUNDLE="$FACET_ROOT/desktop/src-tauri/target/release/bundle/macos/Facet.app"

facet_note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
facet_warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
facet_die() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

# Echo the bundle to use (`FACET_APP` overrides the default build output).
facet_bundle() {
  local bundle="${FACET_APP:-$FACET_DEFAULT_BUNDLE}"
  [[ -d "$bundle" ]] || facet_die "no app bundle at $bundle — build it first: scripts/build.sh --stub"
  printf '%s' "$bundle"
}

# Echo the bundle's main executable. The name comes from Info.plist
# (`CFBundleExecutable`, currently `facet`) rather than being assumed.
facet_executable() {
  local bundle="$1" name
  name="$(plutil -extract CFBundleExecutable raw "$bundle/Contents/Info.plist" 2>/dev/null)" ||
    facet_die "cannot read CFBundleExecutable from $bundle/Contents/Info.plist"
  printf '%s/Contents/MacOS/%s' "$bundle" "$name"
}

# Echo the sidecar binary embedded in the bundle. Tauri copies
# `binaries/crystalline-<target-triple>` here as `crystalline`; it is absent
# unless the build installed one (see scripts/dev-sidecar.sh, scripts/build.sh).
facet_sidecar() { printf '%s/Contents/MacOS/crystalline' "$1"; }

# Echo the first free TCP port at or above $1, so the app and this script agree
# on the port instead of the app falling back to a random one.
facet_free_port() {
  local port="$1" i
  for ((i = 0; i < 50; i++)); do
    if ! nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      printf '%s' "$port"
      return 0
    fi
    port=$((port + 1))
  done
  return 1
}

# Poll an HTTP endpoint until it answers; echo the body on success.
# usage: facet_wait_http <url> <timeout_secs>
facet_wait_http() {
  local url="$1" timeout="$2" body
  local deadline=$((SECONDS + timeout))
  while ((SECONDS < deadline)); do
    if body="$(curl -fsS --max-time 2 "$url" 2>/dev/null)"; then
      printf '%s' "$body"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

# Wait for a log file to contain an extended-regex line.
# usage: facet_wait_log <file> <pattern> <timeout_secs>
facet_wait_log() {
  local file="$1" pattern="$2" timeout="$3"
  local deadline=$((SECONDS + timeout))
  while ((SECONDS < deadline)); do
    if [[ -f "$file" ]] && grep -qE "$pattern" "$file" 2>/dev/null; then
      return 0
    fi
    sleep 0.3
  done
  return 1
}

# ─── Crystalline engine (live mode) ─────────────────────────────────────────
#
# Shared by `run-app-live.sh` and `smoke-app.sh`. FACET_ENGINE_PID is set only
# when this process started the engine, so a reused instance is never stopped.

FACET_ENGINE_PID=""

# Ensure an engine answers on <url>/health, starting `gleam run` from <dir> if
# not. usage: facet_engine_up <url> <dir> <db> <log> <timeout_secs>
facet_engine_up() {
  local url="$1" dir="$2" db="$3" log="$4" timeout="$5" body
  local port="${url##*:}"
  if curl -fsS --max-time 2 "$url/health" >/dev/null 2>&1; then
    facet_note "reusing the Crystalline already listening on $url"
    return 0
  fi

  [[ -d "$dir" ]] || facet_die "no Crystalline checkout at $dir (override with CRYSTALLINE_DIR)"
  command -v gleam >/dev/null || facet_die "gleam not found in PATH"

  facet_note "starting Crystalline in $dir (log: $log)"
  (
    cd "$dir" &&
      CRYSTALLINE_DAEMON=0 CRYSTALLINE_DB="$db" PORT="$port" gleam run
  ) >>"$log" 2>&1 &
  FACET_ENGINE_PID=$!
  # Keep the shell from announcing the engine we kill later ("Terminated: 15").
  disown 2>/dev/null || true

  if ! body="$(facet_wait_http "$url/health" "$timeout")"; then
    facet_warn "the engine did not answer on $url/health; last log lines:"
    tail -20 "$log" >&2
    return 1
  fi
  facet_note "engine healthy: $body"
}

# Stop the engine started by facet_engine_up. usage: facet_engine_down <url>
facet_engine_down() {
  local url="$1" port="${1##*:}" pids deadline pid
  pid="$FACET_ENGINE_PID"
  [[ -n "$pid" ]] || return 0
  FACET_ENGINE_PID=""

  facet_note "stopping Crystalline"
  kill -TERM "$pid" 2>/dev/null || true

  # `gleam run` leaves the BEAM behind when only the wrapper is signalled, so
  # stop whatever still holds the engine port.
  pids="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  [[ -n "$pids" ]] && kill -TERM $pids 2>/dev/null || true
  deadline=$((SECONDS + 15))
  while ((SECONDS < deadline)); do
    lsof -tiTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 || return 0
    sleep 0.5
  done

  pids="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  [[ -n "$pids" ]] && kill -KILL $pids 2>/dev/null || true
  return 0
}

# Ask the app to quit through LaunchServices, then escalate SIGTERM/SIGKILL.
# usage: facet_quit_app <pid> [grace_secs]
facet_quit_app() {
  local pid="$1" grace="${2:-10}"
  local deadline=$((SECONDS + grace))
  osascript -e 'tell application id "com.facet.desktop" to quit' >/dev/null 2>&1 || true
  while ((SECONDS < deadline)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.2
  done

  facet_warn "app pid $pid ignored the quit event — sending SIGTERM"
  kill -TERM "$pid" 2>/dev/null || true
  deadline=$((SECONDS + grace))
  while ((SECONDS < deadline)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.2
  done

  facet_warn "app pid $pid still alive — sending SIGKILL"
  kill -KILL "$pid" 2>/dev/null || true
  sleep 0.5
  kill -0 "$pid" 2>/dev/null && return 1
  return 0
}
