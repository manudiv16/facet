# Project agent memory

Facet is the interface layer for the Crystalline engine: a Gleam CLI plus a shared
HTTP client in `src/`, and a Tauri/SvelteKit desktop app in `desktop/`.
`README.md` is authoritative for the architecture, CLI reference and environment
variables — read it rather than duplicating that detail here.

## Validation commands

- Gleam CLI (repo root): `gleam test`, `gleam build`.
- Claude Code plugin skills (`integrations/claude-code/`): `gleam test` covers the
  command drift suite; `scripts/check-skill-exec.sh` drives the real CLI against the
  Crystalline stand-in.
- Desktop frontend (`desktop/`): `npm install`, then `npm test` (Vitest),
  `npm run check` (svelte-check; 0 errors expected) and `npm run build`.
- Tauri shell: run `scripts/dev-sidecar.sh` first, then `cd desktop/src-tauri && cargo build`.

## Crystalline stand-in

`scripts/crystalline-stub.mjs` is the accepted standalone stand-in for the Crystalline
sidecar, so the shell can be developed and validated before the engine ships a native
binary. It must mirror the engine's HTTP contract, including permissive CORS headers —
the shell fetches it cross-origin, both from the Vite dev server and from the Tauri
webview. Start it with `PORT=<free port> node scripts/crystalline-stub.mjs`; when the
default `http://localhost:8787` is taken, point the frontend elsewhere with
`VITE_CRYSTALLINE_URL`.

`scripts/dev-sidecar.sh` installs that stub as
`desktop/src-tauri/binaries/crystalline-<target-triple>` (gitignored). Without that file
the Tauri build script fails on the `externalBin` resource check, even though the Rust
code compiles.

## Sharp edges

- Any desktop script that touches SvelteKit must run `svelte-kit sync` first:
  `desktop/tsconfig.json` extends the generated `desktop/.svelte-kit/tsconfig.json`,
  which is absent in a fresh checkout. `npm test`, `npm run check` and `npm run build`
  already do this.
- A `//` comment left in Svelte markup (outside `<script>`/`<style>`) is rendered as
  literal page text. Keep component header comments inside `<script>` or use `<!-- -->`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
