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
-export([getenv/1, putenv/2, unsetenv/1, arguments/0]).

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
