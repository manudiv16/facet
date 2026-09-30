# Facet for Claude Code

A Claude Code plugin that lets a coding agent drive the Crystalline engine without
leaving its loop. Every skill is a thin wrapper over the `facet` CLI: the CLI stays the
single source of truth for base URL, bearer token, JSON output and error handling. The
plugin ships no HTTP client of its own.

```
integrations/claude-code/
├── .claude-plugin/plugin.json   manifest (name, version, description, author, license)
├── README.md                    this file
└── skills/<operation>/SKILL.md  one skill per operation (front matter + body)
```

## Skills

| Skill | Command it runs | Status |
| --- | --- | --- |
| `add-task` | `facet --json task add "<title>" …` | active |
| `update-task` | `facet --json task update <task-id> …` | active |
| `archive-task` | `facet --json task delete <task-id> [--cascade]` | active |
| `read-blockers` | `facet --json task blockers <task-id>` | active |
| `read-sections` | `facet --json task sections <task-id>` | active |
| `edit-section` | read + append only; in-place edit pending | pending (crystalline#16) |
| `list-flow-templates` | `facet --json flow templates [show <template-id>]` | active |
| `start-flow` | `facet --json flow start <task-id> <template-id>` | active |
| `complete-flow-step` | `facet --json flow complete-step <instance-id> <step-id> --output "<result>"` | active |
| `read-execution-logs` | `facet --json exec logs <exec-id> [--limit N] [--before SEQ]` | active |

A skill marked `status: pending` in its front matter documents a workflow the CLI does
not implement yet; its planned command sits in a `text` block prefixed with `PENDING:`
so the drift test never mistakes it for a runnable example.

## Requirements

- **`facet` on `PATH`.** The skills invoke `facet` directly. The repository does not
  ship an installer; a wrapper over `gleam run` is enough:

  ```sh
  mkdir -p ~/.local/bin
  cat > ~/.local/bin/facet <<'EOF'
  #!/bin/sh
  # facet CLI wrapper — run the Gleam entry point from the repository checkout.
  cd /path/to/facet || exit 1
  exec gleam run --no-print-progress -m facet_cli -- "$@"
  EOF
  chmod +x ~/.local/bin/facet
  ```

  `gleam` must be on `PATH` too when the wrapper is used. Compile chatter from
  `gleam run` is suppressed by `--no-print-progress`; stdout carries only the command
  output, stderr carries only `facet: <message>` on failure.
- **A Crystalline instance.** Skills read configuration from the environment the CLI
  already owns — no plugin-specific configuration exists:

  | Variable | Default | Purpose |
  | --- | --- | --- |
  | `FACET_URL` | `http://localhost:8787` | Crystalline base URL |
  | `FACET_TOKEN` | — | Bearer token for a remote instance |

  Per-invocation `--url`/`--token` override the environment; the skills never pass
  credentials themselves, so tokens stay out of the skill files.
- **Engine coverage.** `read-sections`, the read half of `edit-section` and the
  append in `edit-section` need a Crystalline build that serves
  `GET/POST /api/v1/tasks/:id/sections` (crystalline#16). Older builds answer 404 and
  `facet` exits 1 with the engine's body on stderr; the skills say so instead of
  retrying.

## Install

- Load the plugin straight from this checkout:

  ```sh
  claude --plugin-dir /path/to/facet/integrations/claude-code
  ```

- Or add the directory to a plugin marketplace entry and install it from
  `/plugin` inside a session.

The skills then appear as `/facet:add-task`, `/facet:start-flow`, … (plugin-prefixed)
and are also picked up automatically when the conversation matches their
`description`.

## Verification

Two layers live in the repository, both green in CI terms (`gleam test`):

- `test/facet_skill_drift_test.gleam` — parses every `facet …` example in
  `skills/*/SKILL.md` (fenced `sh`/`bash` blocks and inline `` `facet …` `` spans) with
  the CLI's own parser, `facet/cli/args`. A skill that references a subcommand or flag
  the CLI no longer implements fails the suite. It also pins the skill roster and the
  front matter (`name`, `description`, `status`).
- `scripts/check-skill-exec.sh` — starts `scripts/crystalline-stub.mjs` on a free
  port, exposes the CLI as `facet` on PATH the way this README prescribes, runs the
  real `task add` and `task blockers` commands from the skills, and asserts the JSON
  that comes back. It does not run `flow templates`: the stand-in wraps that response
  in `{"templates": […]}` while Crystalline returns a bare array, which is what
  `facet` decodes — a stand-in divergence, reported rather than patched here.

```sh
gleam test
scripts/check-skill-exec.sh
```
