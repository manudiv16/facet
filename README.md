# Facet

CLI and Tauri desktop client for [Crystalline](https://github.com/manudiv16/crystalline) — an embedded AI-agent workflow orchestration engine written in Gleam.

```
Facet CLI ──┐
            ├→ HTTP → Crystalline (Wisp + Mist) → libsql (file: | libsql://turso)
Facet Tauri ┘
```

Facet is the interface layer; Crystalline is the engine. Both surfaces share one HTTP client.

### Modes

- **Embedded** — Facet spawns the Crystalline binary as a sidecar and talks to it over localhost HTTP.
- **Remote** — Facet points at a deployed Crystalline instance (Turso-hosted or self-hosted).

Identical code in both modes; only the base URL changes.

## Status

- **#1 HTTP client + shared domain models** — implemented (`src/facet/client.gleam`, `src/facet/models.gleam`).
- **#2 CLI surface** — implemented (`src/facet_cli.gleam`, `src/facet/cli/`).
- **#3+ Tauri shell and UI** — pending.

Work is tracked as dependency-linked issues:

| # | Task | Blocked by |
| --- | --- | --- |
| [#1](https://github.com/manudiv16/facet/issues/1) | HTTP client + shared domain models | crystalline#5 |
| [#2](https://github.com/manudiv16/facet/issues/2) | CLI surface: tasks, flows, executions | #1 |
| [#3](https://github.com/manudiv16/facet/issues/3) | Tauri shell: sidecar packaging | #1 |
| [#4](https://github.com/manudiv16/facet/issues/4) | Task management UI | #3, crystalline#6 |
| [#5](https://github.com/manudiv16/facet/issues/5) | Flow graph visualizer | #3, crystalline#7 |
| [#6](https://github.com/manudiv16/facet/issues/6) | Execution history and session log viewer | #3, crystalline#8 |

## Development

### CLI

```sh
gleam run   # Run the CLI
gleam test  # Run the tests
gleam build # Compile
```

Command reference:

```
facet [--url <base-url>] [--token <token>] [--json] <command> [args...]

facet health
facet task add <title> [--level epic|ticket|task] [--priority low|medium|high|critical] [--tag <t>]
facet task list [--ready] [--status <s>] [--limit <n>] [--offset <n>]
facet task show <id> | update <id> [--flags] | delete <id> [--cascade]
facet task depend <id> <depends-on> | undepend <id> <depends-on> | blockers <id>
facet flow templates         # or: flow templates show <id>
facet flow start <task-id> <template-id>
facet flow status <instance-id>
facet flow advance <instance-id>            # prints the engine Action
facet flow complete-step <inst> <step> --output "<result>"
facet flow input <instance-id> "<text>"
facet flow reject <instance-id> [--reason "..."]
facet exec history <task-id> | show <exec-id> | active
facet exec logs <exec-id> [--limit N] [--before SEQ]
```

- `--ready` lists only unblocked tasks (`/tasks/ready`); `--json` switches to machine-readable output.
- Flow commands implement the human-in-the-loop loop: `advance` prints the action and the next command to run.
- `exec logs` pages newest-first; when a page fills up it suggests `--before <oldest sequence>` to continue.
- Errors go to stderr as `facet: <message>` with exit status 1; success (and `--help`) exit 0.

### Desktop (Tauri)

The desktop shell lives in `desktop/` (SvelteKit/Vite frontend + Rust Tauri app in
`desktop/src-tauri/`). It spawns the Crystalline binary as a sidecar and talks to it over
localhost HTTP.

The sidecar is discovered at `desktop/src-tauri/binaries/crystalline-<target-triple>`.
Build the real binary with `scripts/build.sh` (requires a Crystalline checkout) or install
the development stub with `scripts/dev-sidecar.sh` and run `scripts/build.sh --stub`:

```sh
scripts/dev-sidecar.sh   # install the stub under the platform-suffixed name
cd desktop && cargo tauri dev   # develop: sidecar + hot-reloading UI
scripts/build.sh --stub  # or with a real binary: scripts/build.sh
# Artifacts land in desktop/src-tauri/target/release/bundle/macos (or -windows/)…
```

`cargo tauri dev` and the bundled app expect `desktop/src-tauri/sidecar.toml`-compiled
values (binary name, preferred port, DB path). On macOS the database defaults to
`~/Library/Application Support/Facet/crystalline.db`.

| Variable | Default | Purpose |
| --- | --- | --- |
| `FACET_URL` | `http://localhost:8787` | Crystalline base URL; when set, no sidecar is spawned |
| `FACET_TOKEN` | — | Bearer token for a remote instance |
| `CRYSTALLINE_PORT` | `8787` | Preferred sidecar port (a random free port is used if taken) |
| `CRYSTALLINE_DB` | *platform data dir* | Override the sidecar database path |

## Related

- [Crystalline](https://github.com/manudiv16/crystalline) — Backend engine (Gleam + libsql)
