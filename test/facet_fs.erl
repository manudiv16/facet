-module(facet_fs).
-export([read_file/1, list_dir/1]).

%% Minimal file access for tests that must read repository files (the skill
%% drift suite). Both calls resolve paths relative to the working directory of
%% `gleam test`, which is the repository root, and answer
%% {ok, Value} | {error, nil} so callers get a Gleam Result.

read_file(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> {ok, Bin};
        {error, _} -> {error, nil}
    end.

list_dir(Path) ->
    case file:list_dir(Path) of
        {ok, Names} ->
            {ok, [unicode:characters_to_binary(Name) || Name <- Names]};
        {error, _} ->
            {error, nil}
    end.
