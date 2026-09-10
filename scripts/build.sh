#!/usr/bin/env bash
#
# Build the Facet desktop bundle.
#
# Steps:
#   1. Locate (or build) the Crystalline binary and copy it into
#      `desktop/src-tauri/binaries/` with the platform-specific suffix Tauri
#      expects (`crystalline-<target-triple>[.exe]`).
#   2. Ensure application icons exist.
#   3. Install frontend dependencies and run `tauri build`, which compiles the
#      Rust release and produces the platform bundle (.app / .exe / .deb ...).
#
# Usage:
#   scripts/build.sh                 # use the real Crystalline binary
#   scripts/build.sh --stub          # use the dev stub (no Crystalline needed)
#
# Environment:
#   CRYSTALLINE_BIN   path to a prebuilt Crystalline executable
#   CRYSTALLINE_DIR   Crystalline source checkout (default: ../crystalline)
#   TARGET_TRIPLE     override the Rust target triple (default: host)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP="$ROOT/desktop"
TAURI_DIR="$DESKTOP/src-tauri"
BIN_DIR="$TAURI_DIR/binaries"
BINARY_NAME="crystalline"
PYTHON="${PYTHON:-python3}"

USE_STUB=0
for arg in "$@"; do
  case "$arg" in
    --stub) USE_STUB=1 ;;
    -h | --help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

command -v cargo >/dev/null || die "cargo not found in PATH"
command -v rustc >/dev/null || die "rustc not found in PATH"

TARGET_TRIPLE="${TARGET_TRIPLE:-$(rustc -vV | awk '/^host:/ {print $2}')}"
EXE_SUFFIX=""
case "$TARGET_TRIPLE" in *windows*) EXE_SUFFIX=".exe" ;; esac
DEST="$BIN_DIR/${BINARY_NAME}-${TARGET_TRIPLE}${EXE_SUFFIX}"

CRYSTALLINE_DIR="${CRYSTALLINE_DIR:-$ROOT/../crystalline}"
CRYSTALLINE_BIN="${CRYSTALLINE_BIN:-}"

# Print the path of a Crystalline executable, or nothing.
resolve_crystalline() {
  if [[ -n "$CRYSTALLINE_BIN" ]]; then
    [[ -f "$CRYSTALLINE_BIN" ]] || die "CRYSTALLINE_BIN=$CRYSTALLINE_BIN does not exist"
    printf '%s' "$CRYSTALLINE_BIN"
    return
  fi

  local candidates=(
    "$CRYSTALLINE_DIR/build/${BINARY_NAME}${EXE_SUFFIX}"
    "$CRYSTALLINE_DIR/target/release/${BINARY_NAME}${EXE_SUFFIX}"
    "$CRYSTALLINE_DIR/${BINARY_NAME}${EXE_SUFFIX}"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return
    fi
  done
}

install_sidecar() {
  mkdir -p "$BIN_DIR"
  if [[ "$USE_STUB" == 1 ]]; then
    note "installing development stub sidecar"
    cp "$ROOT/scripts/crystalline-stub.mjs" "$DEST"
    chmod +x "$DEST"
  else
    local binary
    binary="$(resolve_crystalline)"
    if [[ -z "$binary" ]]; then
      die "no Crystalline binary found. Build Crystalline and set CRYSTALLINE_BIN, or pass --stub."
    fi
    note "embedding Crystalline binary: $binary"
    cp "$binary" "$DEST"
    chmod +x "$DEST"
  fi
  note "sidecar ready: $DEST"
}

ensure_icons() {
  if [[ -f "$TAURI_DIR/icons/icon.icns" || -f "$TAURI_DIR/icons/icon.ico" ]]; then
    return
  fi
  note "generating application icons"
  local source="$TAURI_DIR/icon-source.png"
  "$PYTHON" "$ROOT/scripts/generate-icon.py" "$source" || die "icon generation failed"
  (cd "$DESKTOP" && cargo tauri icon "$source")
  rm -f "$source"
}

bundles_for_os() {
  case "$(uname -s)" in
    Darwin) echo "app" ;;
    Linux) echo "deb,appimage" ;;
    MINGW* | MSYS* | CYGWIN*) echo "nsis" ;;
    *) echo "all" ;;
  esac
}

main() {
  install_sidecar
  ensure_icons
  note "installing frontend dependencies"
  (cd "$DESKTOP" && npm install --no-audit --no-fund)
  note "building Tauri release bundle"
  local bundles
  bundles="$(bundles_for_os)"
  (cd "$DESKTOP" && cargo tauri build --bundles "$bundles")
  note "done — artifacts under desktop/src-tauri/target/release/bundle/"
}

main
