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
facet [--url <base-url>] [--token <token>] [--project <id|slug>] [--json] <command> [args...]

facet health
facet init <slug> [--name <name>]         # resolve/create a project and make it the default scope
facet path <task-id>                      # ordered ancestor chain root -> task
facet stop <instance-id>                  # cancel a running flow execution
facet task add <title> [--level epic|ticket|task] [--priority low|medium|high|critical] [--tag <t>]
facet task list [--ready] [--status <s>] [--limit <n>] [--offset <n>]
facet task show <id> | update <id> [--flags] | delete <id> [--cascade]
facet task depend <id> <depends-on> | undepend <id> <depends-on> | blockers <id>
facet task sections <id>                  # GET /tasks/:id/sections (crystalline#16)
facet task section add <id> --type <t> --content "<text>"
facet task ref <id> <path> [--line-start N --line-end N --name X --description Y] [--type <t>] [--content <text>]
facet task unref <id> <section-id>
facet artifact <task-id> list
facet artifact <task-id> get <name> | delete <name>
facet artifact <task-id> put <name> --content <json|->   # `-` reads stdin
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
  `--json` echoes the engine's envelopes verbatim — `flow start` answers
  `{"instance", "execution"}` and `advance`/`complete-step`/`input`/`reject` answer
  `{"execution", "action"}`, with the action tagged `type`.
- `flow status` reads `GET /api/v1/flows/:instance-id`, which the engine does not serve yet: it
  addresses instances per task (`GET /api/v1/tasks/:task-id/flow`), so the command surfaces the
  engine's `404` rather than a state.
- `stop` cancels a `running` or `awaiting_input` execution and prints the cancelled execution. Pending
  or already-terminal executions answer `409` naming their status, and a later `flow advance` answers
  `409` with the engine's `…was cancelled` message verbatim.
- `exec logs` pages newest-first; when a page fills up it suggests `--before <oldest sequence>` to continue.
- Errors go to stderr as `facet: <message>` with exit status 1; success (and `--help`) exit 0.
- The same commands are exposed to Claude Code as skills under
  [`integrations/claude-code/`](integrations/claude-code/); `gleam test` fails if a
  skill references a command this reference no longer has.

#### Project scope

`facet init <slug> [--name <name>]` looks the project up by slug, creates it with `POST /api/v1/projects`
when it does not exist (a `409` on a lost race re-reads it), and persists the slug in the client config
file. Every later scoped request sends it as `X-Crystalline-Project`, which accepts a project **id or
slug**; the engine falls back to its `default` project when the header is absent, and answers `404`
(`Unknown project: <key>`) when it names no project — the CLI turns that into
`run `facet init <slug>` to create it, or pass --project <id|slug>`.

Scope precedence, most specific first:

| Priority | Source |
| --- | --- |
| 1 | `--project <id\|slug>` global flag |
| 2 | `FACET_PROJECT` environment variable |
| 3 | config file written by `facet init` |
| 4 | absent — the engine's `default` project |

The config file is JSON (`{"project": "<id-or-slug>"}`) at `$FACET_CONFIG`, else
`$XDG_CONFIG_HOME/facet/config.json`, else `$HOME/.config/facet/config.json`. A missing or malformed
file means "no persisted project", never an error.

#### Code references

A code reference is **not** a separate entity: the engine stores it as the `code_ref` field of a section
(`path`, `line_start`, `line_end`, `name`, `description`). The CLI mirrors that:

- `facet task ref <task-id> <path> [flags]` is `POST /api/v1/tasks/:task_id/sections` with
  `code_ref:{…}`. `--type` (default `context`) picks the section type and `--content` (default the code
  path) the section text, so the reference always lives in a real section.
- `facet task unref <task-id> <section-id>` is `PATCH /api/v1/sections/:id` with `{"code_ref": null}`.
- `facet task sections <task-id>` shows the reference inline (`code ref: src/main.gleam:10-20 (main)`).

Artifacts are arbitrary JSON documents stored under a task-scoped logical name:
`GET /api/v1/tasks/:task_id/artifacts` (list, project-scoped), and
`GET|PUT|DELETE /api/v1/tasks/:task_id/artifacts/:logical_name` (by explicit id and name, so they stay
reachable without a scope). `put` sends `{"content": <any JSON>}` and the content round-trips exactly;
`--content -` reads the JSON from stdin.

| Variable | Default | Purpose |
| --- | --- | --- |
| `FACET_URL` | `http://localhost:4920` | Crystalline base URL for the CLI |
| `FACET_TOKEN` | — | Bearer token for a remote instance |
| `FACET_PROJECT` | — | Default project scope (id or slug); overrides the config file |
| `FACET_CONFIG` | `$XDG_CONFIG_HOME/facet/config.json` or `$HOME/.config/facet/config.json` | Override the config file path |

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

#### Running the built app

`scripts/build.sh --stub` leaves `desktop/src-tauri/target/release/bundle/macos/Facet.app`
(~12.5 MB, arm64, unsigned). `Contents/MacOS/crystalline` is the sidecar **embedded at build
time** — whatever `desktop/src-tauri/binaries/` held when `tauri build` ran, not something the
app looks up at launch.

Three scripts cover the run modes; all of them resolve the bundle (override with `FACET_APP`),
write the app log under `/tmp`, and run in the foreground until the window closes or you press
Ctrl-C (`--detach` returns to the shell and leaves the app running).

```sh
scripts/run-app-stub.sh          # stub mode — no engine required
scripts/run-app-live.sh          # live mode — starts Crystalline, then the app
scripts/smoke-app.sh [--live]    # non-interactive start/assert/quit check
```

**stub mode** — the app spawns the development stub (`scripts/crystalline-stub.mjs`, installed
as `Contents/MacOS/crystalline`) and talks to it over localhost HTTP on port 8787, or the next
free port (`CRYSTALLINE_PORT`). No engine, no checkout, no network.

**live mode** — the real engine serves the app over HTTP:

```sh
cd ~/Documents/github/crystalline && \
  CRYSTALLINE_DAEMON=0 CRYSTALLINE_DB=file:/tmp/facet-app-live.db PORT=5010 gleam run
```

`scripts/run-app-live.sh` runs exactly that (`CRYSTALLINE_DIR`, `CRYSTALLINE_PORT`,
`CRYSTALLINE_DB` override it), waits for `http://127.0.0.1:5010/health`, then launches the app
with `FACET_URL=http://127.0.0.1:5010`. `FACET_URL` is read **at run time** by the Rust shell
(`determine_mode` in `desktop/src-tauri/src/sidecar.rs`); a non-empty value selects remote mode,
so the app never spawns a sidecar and never forwards provider keys to it. The app's own log
confirms it with `Remote mode: http://127.0.0.1:5010`. When the app exits, the script stops the
engine it started (an engine that was already listening on the port is reused and left alone).

Launching with `open -a` instead of the scripts does **not** inherit your shell environment, so
live mode needs the variables passed explicitly: `open -a .../Facet.app --env
FACET_URL=http://127.0.0.1:5010`. The scripts launch `Contents/MacOS/` directly for this reason.

What each mode actually exercises:

| UI area | stub mode | live mode |
| --- | --- | --- |
| Connection banner, reported version | stub's `/health` (`0.1.0-stub`) | engine's `/health` (`1.0.0`) |
| Tasks: list, detail, create, edit, status, delete | yes | yes |
| Dependencies / blockers | yes | yes |
| Executions: history, active, session log | yes — seeded fixtures | yes — whatever the engine ran |
| A task's flow state | yes — seeded | yes (404 while the task has no bound flow) |
| Flow template browser | yes — seeded registry | yes — engine's templates |
| Sections / code refs | `GET /tasks/:id/sections` is a hard 404 in the stub | yes |
| Artifacts panel | route absent → request fails inline | yes |
| Template authoring (create/edit/transitions) | not implemented → write fails | yes |
| Flow controls (assign, advance, complete, input, reject) | not implemented | yes |
| Settings / provider keys (OS keychain) | yes — native commands, backend-independent | yes |

So the stub demonstrates the full read surface and the task-write path; anything it does not
implement still renders, but its request fails and the UI shows the error inline.

Embedded mode driven by the **real** engine is deliberately unsupported: `bundle.externalBin`
carries a single file, and Crystalline is a Gleam/OTP release (a compiled `build/` tree plus an
Erlang runtime), not one executable. Use live mode for a real engine.

#### Gatekeeper

A bundle built here has no quarantine attribute, so it opens normally; the flag appears only
after the `.app` travels through a download, AirDrop or another machine. When macOS refuses to
open it ("Apple cannot check it for malicious software") because the bundle is unsigned, either
right-click the app in Finder → **Open** → **Open**, or clear the flag once:

```sh
xattr -dr com.apple.quarantine desktop/src-tauri/target/release/bundle/macos/Facet.app
```

#### Provider API keys

The Settings screen (`/settings` in the sidebar) is the credential entry point for the
embedded engine: keys for Anthropic, OpenAI, Google, Groq, Mistral and OpenRouter can be
added, replaced, or removed there. Keys are stored in the OS keychain (macOS Keychain,
Windows Credential Manager, or the Linux Secret Service) — never in config files, the app
bundle, or logs — and the app only ever reads back which providers are configured, never
key values. When the embedded sidecar spawns, each configured key is forwarded as its
conventional environment variable (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, …). Remote mode
(`FACET_URL`) never receives them: a remote instance manages its own credentials.

| Variable | Default | Purpose |
| --- | --- | --- |
| `FACET_URL` | unset → spawn the sidecar | Remote Crystalline base URL, read at run time; when set, no sidecar is spawned |
| `CRYSTALLINE_PORT` | `8787` | Preferred sidecar port (a random free port is used if taken) |
| `CRYSTALLINE_DB` | *platform data dir* | Override the sidecar database path |
| `VITE_CRYSTALLINE_URL` | `http://localhost:8787` | Browser-only fallback base URL (ignored inside Tauri, where `FACET_URL`/the sidecar port decides) |
| `VITE_CRYSTALLINE_TOKEN` | — | Bearer token compiled into the frontend at `npm run build` time; the desktop app has no run-time token variable. The local engine disables auth unless you set `CRYSTALLINE_API_TOKEN` on it |

The CLI's `FACET_TOKEN` (see above) is a separate, run-time variable and is unaffected.

## Related

- [Crystalline](https://github.com/manudiv16/crystalline) — Backend engine (Gleam + libsql)
