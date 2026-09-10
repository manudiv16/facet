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

Scaffolded — awaiting implementation.

Work is tracked as dependency-linked issues:

| # | Task | Blocked by |
|---|---|---|
| [#1](https://github.com/manudiv16/facet/issues/1) | HTTP client + shared domain models | crystalline#5 |
| [#2](https://github.com/manudiv16/facet/issues/2) | CLI surface: tasks, flows, executions | #1 |
| [#3](https://github.com/manudiv16/facet/issues/3) | Tauri shell: sidecar packaging | #1 |
| [#4](https://github.com/manudiv16/facet/issues/4) | Task management UI | #3, crystalline#6 |
| [#5](https://github.com/manudiv16/facet/issues/5) | Flow graph visualizer | #3, crystalline#7 |
| [#6](https://github.com/manudiv16/facet/issues/6) | Execution history and session log viewer | #3, crystalline#8 |

## Development

```sh
gleam run   # Run the CLI
gleam test  # Run the tests
gleam build # Compile
```

| Variable | Default | Purpose |
|---|---|---|
| `FACET_URL` | `http://localhost:8787` | Crystalline base URL; when set, no sidecar is spawned |
| `FACET_TOKEN` | — | Bearer token for a remote instance |

## Related

- [Crystalline](https://github.com/manudiv16/crystalline) — Backend engine (Gleam + libsql)
