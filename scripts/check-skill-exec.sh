#!/usr/bin/env bash
#
# Execution check for the Claude Code plugin skills (integrations/claude-code).
#
# Starts the accepted Crystalline stand-in (scripts/crystalline-stub.mjs) on a
# free loopback port, exposes the CLI as `facet` on PATH exactly the way
# integrations/claude-code/README.md tells agents to, runs the skill commands
# against the stub and asserts the JSON they print. This is the runtime half of
# the plugin's verification; the static half is `gleam test`
# (test/facet_skill_drift_test.gleam).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STUB="$ROOT/scripts/crystalline-stub.mjs"

command -v node >/dev/null || { echo "node not found" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v gleam >/dev/null || { echo "gleam not found" >&2; exit 1; }

# Free port, then bring the stand-in up on it.
PORT="$(node -e 'const s=require("net").createServer();s.listen(0,"127.0.0.1",()=>{process.stdout.write(String(s.address().port));s.close();})')"
PORT="$PORT" node "$STUB" &
STUB_PID=$!
trap 'kill "$STUB_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
  curl -sf "http://127.0.0.1:$PORT/health" >/dev/null && break
  sleep 0.1
done
curl -sf "http://127.0.0.1:$PORT/health" >/dev/null || {
  echo "stub did not become ready on port $PORT" >&2
  exit 1
}
echo "stub ready on http://127.0.0.1:$PORT"

# `facet` on PATH — the wrapper the plugin README documents.
BIN_DIR="$(mktemp -d)"
trap 'kill "$STUB_PID" 2>/dev/null || true; rm -rf "$BIN_DIR"' EXIT
cat > "$BIN_DIR/facet" <<EOF
#!/bin/sh
cd "$ROOT" || exit 1
exec gleam run --no-print-progress -m facet_cli -- "\$@"
EOF
chmod +x "$BIN_DIR/facet"
export PATH="$BIN_DIR:$PATH"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# ── skills/add-task ─────────────────────────────────────────────────────────
TITLE="Skill execution check $(date +%s)"
ADD_OUT="$(facet --url "http://127.0.0.1:$PORT" --json task add "$TITLE" --level task --priority high)"
echo "task add -> $ADD_OUT"
printf '%s' "$ADD_OUT" | node -e '
let raw = "";
process.stdin.on("data", (chunk) => (raw += chunk)).on("end", () => {
  const task = JSON.parse(raw);
  const problems = [];
  if (task.title !== process.argv[1]) problems.push("title mismatch");
  if (typeof task.id !== "string" || task.id === "") problems.push("missing id");
  if (task.status !== "todo") problems.push("status is " + task.status);
  if (task.level !== "task") problems.push("level is " + task.level);
  if (task.priority !== "high") problems.push("priority is " + task.priority);
  if (problems.length) {
    console.error(problems.join("; ") + " :: " + raw);
    process.exit(1);
  }
  console.log("asserted task add: id=" + task.id + " status=" + task.status);
});' "$TITLE" || fail "task add payload"
TASK_ID="$(printf '%s' "$ADD_OUT" | node -e 'let r="";process.stdin.on("data",d=>r+=d).on("end",()=>process.stdout.write(JSON.parse(r).id))')"

# ── skills/read-blockers ────────────────────────────────────────────────────
BLOCKERS_OUT="$(facet --url "http://127.0.0.1:$PORT" --json task blockers "$TASK_ID")"
echo "task blockers -> $BLOCKERS_OUT"
printf '%s' "$BLOCKERS_OUT" | node -e '
let raw = "";
process.stdin.on("data", (chunk) => (raw += chunk)).on("end", () => {
  const blockers = JSON.parse(raw);
  if (!Array.isArray(blockers)) {
    console.error("expected an array :: " + raw);
    process.exit(1);
  }
  console.log("asserted blockers: " + blockers.length + " entries");
});' || fail "task blockers payload"

# ── skills/list-flow-templates ──────────────────────────────────────────────
# Not run here; see the note at the bottom of this file for why.

echo "skill execution check passed"

# Deliberately not exercised here: `flow templates`. The stand-in answers
# GET /api/v1/flow-templates with {"templates": [...]} while Crystalline returns a
# bare array (crystalline src/sacrum_gleam/flow/templates.gleam,
# templates_list_to_json) — which is what `facet` decodes, so the command works
# against a real engine but fails to decode against this stand-in. The stub is
# shared infrastructure and the lane brief says to report such a gap rather than
# expand the stub, so it is left untouched; the command is still covered by
# test/facet_skill_drift_test.gleam and by the wire-format test in
# test/facet_cli_app_test.gleam.
