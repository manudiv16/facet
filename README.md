# Facet

CLI and Tauri desktop client for [Crystalline](https://github.com/manudiv16/crystalline) — an embedded AI workflow orchestration engine.

## Architecture

```
Facet CLI ──┐
            ├→ HTTP → Crystalline (Wisp+Mist) → libsql (local | Turso)
Facet Tauri ┘
```

Facet is the interface layer; Crystalline is the engine.

### Modes
- **Embedded**: Facet launches Crystalline as a local sidecar, communicates over localhost HTTP
- **Remote**: Facet connects to a deployed Crystalline instance (Turso-hosted or self-hosted)

Same code, only the connection URL changes.

## Status

🚧 Scaffolded — awaiting implementation. See [crystalline](https://github.com/manudiv16/crystalline) for the engine implementation plan.

## Related
- [Crystalline](https://github.com/manudiv16/crystalline) — Backend engine (Gleam + libsql)
