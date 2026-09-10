-module(facet_stub_server).
-export([
    start/2,
    start_capture/2,
    get_captured/1
]).

%% Start a one-shot HTTP/1.1 stub server on an ephemeral loopback port.
%%
%% `start/2` returns {ListenSocket, Port}; a background process accepts a
%% single connection, replies with the given status and JSON body, then
%% closes.
%%
%% `start_capture/2` additionally returns {ListenSocket, Port, Collector};
%% the received request line is forwarded to the collector process and can be
%% fetched with `get_captured/1` as {Method, PathAndQuery, Body}. This lets
%% tests assert that a client hit exactly the endpoint it should.
start(Status, Body) ->
    {ok, Listen} = new_listener(),
    {ok, Port} = inet:port(Listen),
    spawn(fun() -> serve(Listen, Status, Body) end),
    {Listen, Port}.

start_capture(Status, Body) ->
    {ok, Listen} = new_listener(),
    {ok, Port} = inet:port(Listen),
    Collector = spawn(fun() -> collector(undefined) end),
    spawn(fun() -> serve_capture(Listen, Status, Body, Collector) end),
    {Listen, Port, Collector}.

get_captured(Collector) ->
    Collector ! {get, self()},
    receive
        {captured, Request} -> Request
    after 2000 ->
        undefined
    end.

%% Keep the last captured request; answer sync queries.
collector(Request) ->
    receive
        {capture, New} -> collector(New);
        {get, From} ->
            From ! {captured, Request},
            collector(Request)
    end.

new_listener() ->
    gen_tcp:listen(0, [
        binary,
        {packet, raw},
        {active, false},
        {reuseaddr, true},
        {ip, {127, 0, 0, 1}}
    ]).

serve(Listen, Status, Body) ->
    case gen_tcp:accept(Listen, 10000) of
        {ok, Sock} ->
            _ = gen_tcp:recv(Sock, 0, 5000),
            respond(Sock, Status, Body);
        _ ->
            ok
    end,
    gen_tcp:close(Listen).

serve_capture(Listen, Status, Body, Collector) ->
    case gen_tcp:accept(Listen, 10000) of
        {ok, Sock} ->
            {ok, Request} = gen_tcp:recv(Sock, 0, 5000),
            Collector ! {capture, parse_request(Request)},
            respond(Sock, Status, Body);
        _ ->
            ok
    end,
    gen_tcp:close(Listen).

respond(Sock, Status, Body) ->
    Response = [
        "HTTP/1.1 ",
        integer_to_list(Status),
        " ",
        reason(Status),
        "\r\n",
        "Content-Type: application/json\r\n",
        "Content-Length: ",
        integer_to_list(byte_size(Body)),
        "\r\n",
        "Connection: close\r\n\r\n",
        Body
    ],
    gen_tcp:send(Sock, Response).

%% "METHOD TARGET HTTP/1.1\r\nheaders\r\n\r\nbody" -> [Method, Target, Body]
%% as a list of binaries (easier to decode on the Gleam side).
parse_request(Bin) ->
    [Head, Body] = binary:split(Bin, <<"\r\n\r\n">>),
    [Line | _] = binary:split(Head, <<"\r\n">>),
    [Method, Target | _] = binary:split(Line, <<" ">>, [global]),
    [Method, Target, Body].

reason(200) -> "OK";
reason(201) -> "Created";
reason(202) -> "Accepted";
reason(400) -> "Bad Request";
reason(404) -> "Not Found";
reason(409) -> "Conflict";
reason(500) -> "Internal Server Error";
reason(_) -> "Error".