%% Internal Erlang helpers for the Facet client.
%%
%% Erlang's `os` module takes charlists, not binaries. On modern OTP releases
%% (>= 29) passing a Gleam string (a binary) straight to `os:getenv/1`,
%% `os:putenv/2` or `os:unsetenv/1` raises `badarg`. These wrappers convert
%% binaries to charlists on the way in and back to binaries on the way out so
%% the Gleam side can keep using plain strings.
%%
%% Return conventions (matching the Gleam externals in `facet/config.gleam`):
%%   getenv(Name)    -> binary() | "":   "" when the variable is not set
%%   putenv(Name, Value)  -> boolean():  whether the variable was set
%%   unsetenv(Name)  -> nil:             `ok` mapped to Gleam's `nil`
-module(facet_ffi).
-export([
    getenv/1,
    putenv/2,
    unsetenv/1,
    arguments/0,
    read_file/1,
    write_file/2,
    make_dir/1,
    read_stdin/0
]).

%% The plain arguments the VM was started with (program name excluded).
%% Erlang reports them as charlists; convert to binaries so Gleam sees
%% `List(String)`.
arguments() ->
    [unicode:characters_to_binary(A) || A <- init:get_plain_arguments()].

getenv(Name) ->
    Charlist = to_charlist(Name),
    case os:getenv(Charlist) of
        false -> <<>>;
        undefined -> <<>>;
        Value -> unicode:characters_to_binary(Value)
    end.

putenv(Name, Value) ->
    os:putenv(to_charlist(Name), to_charlist(Value)).

unsetenv(Name) ->
    _ = os:unsetenv(to_charlist(Name)),
    nil.

to_charlist(Binary) ->
    unicode:characters_to_list(Binary).

%% Read a UTF-8 file as a binary; every failure is `{error, nil}` so the
%% caller can treat "missing" and "unreadable" alike.
read_file(Path) ->
    case file:read_file(to_charlist(Path)) of
        {ok, Bin} -> {ok, Bin};
        {error, _} -> {error, nil}
    end.

write_file(Path, Content) ->
    case file:write_file(to_charlist(Path), Content) of
        ok -> {ok, nil};
        {error, Reason} -> {error, format_reason(Reason)}
    end.

%% Create a directory (and its parents) if it does not exist yet.
make_dir(Path) ->
    case filelib:ensure_path(to_charlist(Path)) of
        ok -> {ok, nil};
        {error, Reason} -> {error, format_reason(Reason)}
    end.

%% Read all of standard input to EOF as a binary.
read_stdin() ->
    read_stdin([]).

read_stdin(Acc) ->
    case io:get_chars(standard_io, '', 65536) of
        eof -> unicode:characters_to_binary(lists:reverse(Acc));
        {error, _} -> unicode:characters_to_binary(lists:reverse(Acc));
        Data -> read_stdin([Data | Acc])
    end.

format_reason(Reason) ->
    unicode:characters_to_binary(io_lib:format("~p", [Reason])).
