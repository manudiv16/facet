-module(facet_stderr).
-compile(nowarn_deprecated_catch).
-export([capture/1]).

%% Run `Fun` with the `standard_error` device redirected into a collector
%% process and return `{Result, CapturedText}`.
%%
%% The CLI writes failures with `io.println_error/1`, which sends an
%% `io_request` to the registered `standard_error` process. Swapping that
%% registration for the duration of `Fun` lets a test assert the message
%% really went to stderr rather than stdout. The original device is put back
%% before `capture/1` returns, so a failing assertion still leaves the VM
%% usable.
capture(Fun) ->
    Original = whereis(standard_error),
    unregister(standard_error),
    Collector = spawn(fun() -> loop([]) end),
    true = register(standard_error, Collector),
    Result = catch Fun(),
    Collector ! {stop, self()},
    Captured =
        receive
            {captured, Text} -> Text
        after 5000 -> <<>>
        end,
    case Original of
        undefined -> ok;
        Pid -> true = register(standard_error, Pid)
    end,
    case Result of
        {'EXIT', Reason} -> erlang:error(Reason);
        Value -> {Value, Captured}
    end.

loop(Acc) ->
    receive
        {io_request, From, ReplyAs, Request} ->
            case Request of
                {put_chars, Encoding, Chars} when Encoding =:= unicode;
                                                   Encoding =:= latin1 ->
                    From ! {io_reply, ReplyAs, ok},
                    loop([Chars | Acc]);
                {put_chars, Chars} ->
                    From ! {io_reply, ReplyAs, ok},
                    loop([Chars | Acc]);
                _ ->
                    From ! {io_reply, ReplyAs, {error, enotsup}},
                    loop(Acc)
            end;
        {stop, From} ->
            From ! {captured, unicode:characters_to_binary(lists:reverse(Acc))}
    end.
