#!/usr/bin/env bash
#
# Launch the built Facet.app in **stub mode** — no Crystalline engine.
#
# The app spawns the development stub embedded in the bundle
# (`Contents/MacOS/crystalline`, installed by `scripts/dev-sidecar.sh` before
# `scripts/build.sh --stub`) as its sidecar and talks to it over localhost HTTP.
# See the README's "Running the app" section for what this mode can and cannot
# exercise.
#
# Usage:
#   scripts/run-app-stub.sh [--detach]
#
# Environment:
#   FACET_APP        bundle path (default desktop/src-tauri/target/release/bundle/macos/Facet.app)
#   FACET_APP_LOG    app log file (default /tmp/facet-app-stub.log)
#   CRYSTALLINE_PORT preferred sidecar port (default 8787; the next free port is used if taken)
#   FACET_APP_WAIT   seconds to wait for the sidecar health check (default 30)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/app-common.sh"

DETACH=0
for arg in "$@"; do
  case "$arg" in
    --detach) DETACH=1 ;;
    -h | --help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) facet_die "unknown argument: $arg" ;;
  esac
done

[[ -z "${FACET_URL:-}" ]] ||
  facet_die "FACET_URL is set, which selects remote mode; unset it or use scripts/run-app-live.sh"

BUNDLE="$(facet_bundle)"
EXE="$(facet_executable "$BUNDLE")"
SIDECAR="$(facet_sidecar "$BUNDLE")"
LOG="${FACET_APP_LOG:-/tmp/facet-app-stub.log}"
PORT="$(facet_free_port "${CRYSTALLINE_PORT:-8787}")" ||
  facet_die "no free port at or above ${CRYSTALLINE_PORT:-8787}"

[[ -x "$EXE" ]] || facet_die "missing executable: $EXE"
[[ -x "$SIDECAR" ]] ||
  facet_die "the bundle carries no sidecar at $SIDECAR — rebuild with: scripts/dev-sidecar.sh && scripts/build.sh --stub"

: >"$LOG"
facet_note "bundle:  $BUNDLE"
facet_note "sidecar: $SIDECAR (development stub), port $PORT"
facet_note "log:     $LOG"

env -u FACET_URL CRYSTALLINE_PORT="$PORT" "$EXE" >>"$LOG" 2>&1 &
APP_PID=$!

# The app exits if it cannot create its window (e.g. no GUI session); fail fast
# rather than reporting a healthy launch for a process that is already gone.
sleep 2
kill -0 "$APP_PID" 2>/dev/null || {
  facet_warn "the app exited immediately; last log lines:"
  tail -20 "$LOG" >&2
  exit 1
}

if HEALTH="$(facet_wait_http "http://127.0.0.1:$PORT/health" "${FACET_APP_WAIT:-30}")"; then
  facet_note "sidecar healthy: $HEALTH"
else
  facet_warn "no answer from http://127.0.0.1:$PORT/health within ${FACET_APP_WAIT:-30}s; inspect $LOG"
fi

if ((DETACH)); then
  facet_note "Facet is running (pid $APP_PID) — quit with: osascript -e 'quit app \"Facet\"'"
  exit 0
fi

trap 'kill -TERM "$APP_PID" 2>/dev/null || true' INT TERM
facet_note "Facet is running (pid $APP_PID) — close the window or press Ctrl-C to quit"
wait "$APP_PID" || true
facet_note "Facet exited (the app stops its sidecar on the way out)"
