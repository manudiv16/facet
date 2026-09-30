#!/usr/bin/env bash
#
# Launch the built Facet.app in **live mode** — real Crystalline engine.
#
# Starts the engine from a sibling Crystalline checkout, waits for its
# `/health`, then launches the app with `FACET_URL` set. The app treats a
# non-empty `FACET_URL` as remote mode (`determine_mode` in
# `desktop/src-tauri/src/sidecar.rs`): it never spawns the embedded sidecar and
# never forwards provider keys to the engine. Quitting the app (or Ctrl-C here)
# also stops the engine, unless it was already running when this script began.
#
# Usage:
#   scripts/run-app-live.sh [--detach]
#
# Environment:
#   CRYSTALLINE_DIR  Crystalline checkout (default ~/Documents/github/crystalline)
#   CRYSTALLINE_PORT engine port (default 5010)
#   CRYSTALLINE_DB   engine database URL (default file:/tmp/facet-app-live.db)
#   FACET_APP        bundle path (default desktop/src-tauri/target/release/bundle/macos/Facet.app)
#   FACET_APP_LOG    app log file (default /tmp/facet-app-live.log)
#   FACET_ENGINE_LOG engine log file (default /tmp/facet-engine-live.log)
#   FACET_APP_WAIT   seconds to wait for the engine /health (default 180)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/app-common.sh"

DETACH=0
for arg in "$@"; do
  case "$arg" in
    --detach) DETACH=1 ;;
    -h | --help)
      sed -n '2,25p' "$0"
      exit 0
      ;;
    *) facet_die "unknown argument: $arg" ;;
  esac
done

ENGINE_DIR="${CRYSTALLINE_DIR:-$HOME/Documents/github/crystalline}"
URL="http://127.0.0.1:${CRYSTALLINE_PORT:-5010}"
DB="${CRYSTALLINE_DB:-file:/tmp/facet-app-live.db}"
LOG="${FACET_APP_LOG:-/tmp/facet-app-live.log}"
ENGINE_LOG="${FACET_ENGINE_LOG:-/tmp/facet-engine-live.log}"

BUNDLE="$(facet_bundle)"
EXE="$(facet_executable "$BUNDLE")"
[[ -x "$EXE" ]] || facet_die "missing executable: $EXE"

APP_PID=""

cleanup() {
  [[ -n "$APP_PID" ]] && kill -TERM "$APP_PID" 2>/dev/null || true
  facet_engine_down "$URL"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

facet_engine_up "$URL" "$ENGINE_DIR" "$DB" "$ENGINE_LOG" "${FACET_APP_WAIT:-180}" ||
  facet_die "Crystalline failed to start (see $ENGINE_LOG)"

: >"$LOG"
facet_note "bundle: $BUNDLE"
facet_note "log:    $LOG"

env FACET_URL="$URL" "$EXE" >>"$LOG" 2>&1 &
APP_PID=$!

if facet_wait_log "$LOG" "Remote mode: ${URL}" 30; then
  facet_note "app is in remote mode against $URL (sidecar not spawned)"
else
  kill -0 "$APP_PID" 2>/dev/null || {
    facet_warn "the app exited immediately; last log lines:"
    tail -20 "$LOG" >&2
    exit 1
  }
  facet_warn "no \"Remote mode\" line in $LOG yet; inspect it for errors"
fi

if ((DETACH)); then
  facet_note "Facet is running (pid $APP_PID) against $URL — quit with: osascript -e 'quit app \"Facet\"'"
  facet_note "the engine stays up; stop it with: lsof -tiTCP:${URL##*:} -sTCP:LISTEN | xargs kill"
  # Keep the engine alive after this script exits; facet_engine_down is a no-op
  # shellcheck disable=SC2034
  FACET_ENGINE_PID=""
  exit 0
fi

facet_note "Facet is running (pid $APP_PID) against $URL — close the window or press Ctrl-C to quit"
wait "$APP_PID" || true
facet_note "Facet exited"
