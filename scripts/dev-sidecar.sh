#!/usr/bin/env bash
#
# Install the development stub in place of the Crystalline sidecar.
#
# Tauri looks for `src-tauri/binaries/crystalline-<target-triple>` and copies
# it next to the app binary before `tauri dev`/`tauri build`. This lets the
# shell be developed and tested before Crystalline ships its native binary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT/desktop/src-tauri/binaries"
STUB="$ROOT/scripts/crystalline-stub.mjs"

command -v rustc >/dev/null || { echo "rustc not found" >&2; exit 1; }
TARGET_TRIPLE="$(rustc -vV | awk '/^host:/ {print $2}')"
EXE_SUFFIX=""
case "$TARGET_TRIPLE" in *windows*) EXE_SUFFIX=".exe";; esac
DEST="$BIN_DIR/crystalline-${TARGET_TRIPLE}${EXE_SUFFIX}"

mkdir -p "$BIN_DIR"
cp "$STUB" "$DEST"
chmod +x "$DEST"
echo "installed stub sidecar: $DEST"
