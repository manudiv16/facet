#!/usr/bin/env bash
#
# Smoke-check the built Facet.app: start it, prove it came up, quit it cleanly.
#
# This is not a UI test. Nothing here can see or click the window; it asserts
# what is observable from outside the app:
#
#   1. the app process is still alive a couple of seconds after launch;
#   2. the backend it was told to use answers `/health` (the embedded stub sidecar
#      by default, the real engine with `--live`);
#   3. the app's own log shows the expected mode (`Sidecar listening on …` in
#      stub mode, `Remote mode: …` with `--live`);
#   4. stub mode spawns a sidecar child process, `--live` spawns none;
#   5. a quit request exits the app and the app reaps its sidecar.
#
# Usage:
#   scripts/smoke-app.sh          # stub mode: bundle's embedded stub sidecar
#   scripts/smoke-app.sh --live   # live mode: real engine via FACET_URL
#
# Environment: same overrides as scripts/run-app-stub.sh / scripts/run-app-live.sh.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/app-common.sh"

LIVE=0
for arg in "$@"; do
  case "$arg" in
    --live) LIVE=1 ;;
    -h | --help)
      sed -n '2,22p' "$0"
      exit 0
      ;;
    *) facet_die "unknown argument: $arg" ;;
  esac
done

command -v nc >/dev/null || facet_die "nc not found in PATH"

BUNDLE="$(facet_bundle)"
EXE="$(facet_executable "$BUNDLE")"
[[ -x "$EXE" ]] || facet_die "missing executable: $EXE"

FAILURES=0
check() {
  local label="$1" ok="$2"
  if [[ "$ok" == "0" ]]; then
    printf '  \033[1;32mPASS\033[0m  %s\n' "$label"
  else
    printf '  \033[1;31mFAIL\033[0m  %s\n' "$label"
    FAILURES=$((FAILURES + 1))
  fi
}

if ((LIVE)); then
  MODE="live"
  URL="http://127.0.0.1:${CRYSTALLINE_PORT:-5010}"
  ENGINE_DIR="${CRYSTALLINE_DIR:-$HOME/Documents/github/crystalline}"
  DB="${CRYSTALLINE_DB:-file:/tmp/facet-app-live.db}"
  LOG="${FACET_APP_LOG:-/tmp/facet-app-smoke-live.log}"
  ENGINE_LOG="${FACET_ENGINE_LOG:-/tmp/facet-engine-smoke.log}"
  LAUNCH_ENV=(FACET_URL="$URL")
  facet_note "live mode: engine $URL, app log $LOG"
  facet_engine_up "$URL" "$ENGINE_DIR" "$DB" "$ENGINE_LOG" "${FACET_APP_WAIT:-180}" ||
    facet_die "Crystalline failed to start (see $ENGINE_LOG)"
else
  MODE="stub"
  PORT="$(facet_free_port "${CRYSTALLINE_PORT:-8787}")" ||
    facet_die "no free port at or above ${CRYSTALLINE_PORT:-8787}"
  URL="http://127.0.0.1:$PORT"
  LOG="${FACET_APP_LOG:-/tmp/facet-app-smoke.log}"
  LAUNCH_ENV=(-u FACET_URL CRYSTALLINE_PORT="$PORT")
  facet_note "stub mode: embedded sidecar on port $PORT, app log $LOG"
  [[ -x "$(facet_sidecar "$BUNDLE")" ]] ||
    facet_die "the bundle carries no sidecar — rebuild with: scripts/dev-sidecar.sh && scripts/build.sh --stub"
fi

APP_PID=""
SIDECAR_PID=""

cleanup() {
  [[ -n "$APP_PID" ]] && kill -TERM "$APP_PID" 2>/dev/null || true
  ((LIVE)) && facet_engine_down "$URL" || true
}
trap cleanup EXIT

facet_note "bundle: $BUNDLE"
: >"$LOG"
env "${LAUNCH_ENV[@]}" "$EXE" >>"$LOG" 2>&1 &
APP_PID=$!
facet_note "app pid $APP_PID"

# 1. Survives startup — catches an immediate crash / missing window server.
sleep 2
if kill -0 "$APP_PID" 2>/dev/null; then ALIVE=0; else ALIVE=1; fi
check "app process alive 2s after launch (pid $APP_PID)" "$ALIVE"

# 2. The app resolved a backend and the app itself says which one.
if ((LIVE)); then
  EXPECTED="Remote mode: ${URL}"
else
  EXPECTED="Sidecar listening on ${URL}"
fi
if facet_wait_log "$LOG" "$EXPECTED" 30; then MODE_OK=0; else MODE_OK=1; fi
check "app log shows: $(printf '%q' "$EXPECTED")" "$MODE_OK"

# 3. That backend answers /health.
if HEALTH="$(facet_wait_http "$URL/health" 30)"; then HEALTH_OK=0; else HEALTH_OK=1; fi
check "GET $URL/health -> $HEALTH" "$HEALTH_OK"

# 4. Sidecar process ownership: exactly one in stub mode, none in live mode.
CHILDREN="$(pgrep -P "$APP_PID" 2>/dev/null | tr '\n' ' ' || true)"
if ((LIVE)); then
  if [[ -z "$CHILDREN" ]]; then CHILD_OK=0; else CHILD_OK=1; fi
  check "no sidecar child process in remote mode (children: ${CHILDREN:-none})" "$CHILD_OK"
else
  if [[ -n "$CHILDREN" ]]; then CHILD_OK=0; else CHILD_OK=1; fi
  SIDECAR_PID="$(printf '%s' "$CHILDREN" | awk '{print $1}')"
  check "sidecar child process spawned (pid ${SIDECAR_PID:-none})" "$CHILD_OK"
fi

# 5. Quit reaps the app and its sidecar.
if facet_quit_app "$APP_PID" 10; then QUIT_OK=0; else QUIT_OK=1; fi
check "quit request exited the app" "$QUIT_OK"

if ((!LIVE)) && [[ -n "$SIDECAR_PID" ]]; then
  sleep 1
  if kill -0 "$SIDECAR_PID" 2>/dev/null; then REAP_OK=1; else REAP_OK=0; fi
  check "sidecar (pid $SIDECAR_PID) reaped on shutdown" "$REAP_OK"
fi
APP_PID=""

facet_note "app log ($LOG), lines of interest:"
grep -E "Spawning sidecar|Sidecar listening|Sidecar healthy|Remote mode|Stopping sidecar|Shutting down|Sidecar exited" "$LOG" |
  sed 's/^/    /' || true

echo
if ((FAILURES == 0)); then
  printf '\033[1;32msmoke (%s): PASS\033[0m — %s\n' "$MODE" "$URL"
else
  printf '\033[1;31msmoke (%s): FAIL — %d check(s) failed\033[0m\n' "$MODE" "$FAILURES"
  exit 1
fi
