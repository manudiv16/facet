//// Thin Gleam bindings over `src/facet_ffi.erl`.
////
//// Erlang's `os` module takes charlists, and on modern OTP releases (>= 29)
//// passing a Gleam string (a binary) directly raises `badarg`. These
//// functions convert binaries to charlists and back so callers can keep
//// using plain strings, and convert the VM's charlist arguments to strings.
//// Internal to the client; not part of the public API.

@external(erlang, "facet_ffi", "getenv")
pub fn getenv(name: String) -> String

@external(erlang, "facet_ffi", "putenv")
pub fn putenv(name: String, value: String) -> Bool

@external(erlang, "facet_ffi", "unsetenv")
pub fn unsetenv(name: String) -> Nil

/// The plain arguments the VM was started with (program name excluded).
@external(erlang, "facet_ffi", "arguments")
pub fn arguments() -> List(String)
