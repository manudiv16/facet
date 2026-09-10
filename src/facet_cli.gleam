//// Process entry point of the Facet CLI: read the raw argument list, run the
//// CLI orchestration (`facet/cli/app`) and halt the VM with its exit code.
//// Run with `gleam run` (via `src/facet.gleam`) or `gleam run -m facet_cli`.

import facet/cli/app
import facet/ffi

@external(erlang, "erlang", "halt")
fn erlang_halt(status: Int) -> Nil

pub fn main() -> Nil {
  erlang_halt(app.main(ffi.arguments()))
}
