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

/// Read a UTF-8 text file. `Error(Nil)` covers "missing" and every other I/O
/// failure; callers that tolerate a missing file (the config) treat both as
/// absent.
@external(erlang, "facet_ffi", "read_file")
pub fn read_file(path: String) -> Result(String, Nil)

/// Write a UTF-8 text file, replacing any existing content.
@external(erlang, "facet_ffi", "write_file")
pub fn write_file(path: String, content: String) -> Result(Nil, String)

/// Create a directory and its parents if they do not exist.
@external(erlang, "facet_ffi", "make_dir")
pub fn make_dir(path: String) -> Result(Nil, String)

/// Read standard input to EOF as UTF-8 text (`facet artifact put --content -`).
@external(erlang, "facet_ffi", "read_stdin")
pub fn read_stdin() -> String
