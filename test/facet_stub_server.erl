-module(facet_stub_server).
-export([
    start/2,
    start_capture/2,
    start_capture_script/1,
    get_captured/1,
    get_captured_all/1,
    get_captured_headers/1
]).

%% Start a one-shot HTTP/1.1 stub server on an ephemeral loopback port.
%%
%% `start/2` returns {ListenSocket, Port}; a background process accepts a
%% single connection, replies with the given status and JSON body, then
%% closes.
%%
%% `start_capture/2` additionally returns {ListenSocket, Port, Collector};
%% the received request is forwarded to the collector process and can be
%% fetched with `get_captured/1` as {Method, PathAndQuery, Body}. This lets
%% tests assert that a client hit exactly the endpoint it should.
%%
%% `start_capture_script/1` serves a list of {Status, Body} responses in
%% order, one connection per entry, for commands that make more than one
%% request (e.g. `facet init` looks a project up, then creates it).
%% `get_captured_all/1` returns every request in order and
%% `get_captured_headers/1` the headers of the last one, lowercased as
%% "name: value".
start(Status, Body) ->
    {ok, Listen} = new_listener(),
    {ok, Port} = inet:port(Listen),
    spawn(fun() -> serve(Listen, Status, Body) end),
    {Listen, Port}.

start_capture(Status, Body) ->
    start_capture_script([{Status, Body}]).

start_capture_script(Responses) ->
    {ok, Listen} = new_listener(),
    {ok, Port} = inet:port(Listen),
    Collector = spawn(fun() -> collector([]) end),
    spawn(fun() -> serve_capture(Listen, Responses, Collector) end),
    {Listen, Port, Collector}.

get_captured(Collector) ->
    Collector ! {get, self()},
    receive
        {captured, Request} -> Request
    after 2000 ->
        undefined
    end.

get_captured_all(Collector) ->
    Collector ! {get_all, self()},
    receive
        {captured, Requests} -> Requests
    after 2000 ->
        []
    end.

get_captured_headers(Collector) ->
    Collector ! {get_headers, self()},
    receive
        {captured, Headers} -> Headers
    after 2000 ->
        []
    end.

%% Keep every captured request (newest first); answer sync queries.
collector(Requests) ->
    receive
        {capture, Raw} -> collector([Raw | Requests]);
        {get, From} ->
            From ! {captured, case last_request(Requests) of
                undefined -> undefined;
                Raw -> parse_request(Raw)
            end},
            collector(Requests);
        {get_all, From} ->
            From ! {captured, [parse_request(Raw) || Raw <- lists:reverse(Requests)]},
            collector(Requests);
        {get_headers, From} ->
            Headers = case last_request(Requests) of
                undefined -> [];
                Raw -> headers_of(Raw)
            end,
            From ! {captured, Headers},
            collector(Requests)
    end.

last_request([]) -> undefined;
last_request([Raw | _]) -> Raw.

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

serve_capture(Listen, Responses, Collector) ->
    lists:foreach(
        fun({Status, Body}) ->
            case gen_tcp:accept(Listen, 10000) of
                {ok, Sock} ->
                    case gen_tcp:recv(Sock, 0, 5000) of
                        {ok, Request} ->
                            Collector ! {capture, Request},
                            respond(Sock, Status, Body);
                        _ ->
                            ok
                    end,
                    gen_tcp:close(Sock);
                _ ->
                    ok
            end
        end,
        Responses
    ),
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

%% Header lines of a request, lowercased and formatted "name: value".
headers_of(Bin) ->
    [Head | _] = binary:split(Bin, <<"\r\n\r\n">>),
    [_RequestLine | Lines] = binary:split(Head, <<"\r\n">>, [global]),
    [lower_header(Line) || Line <- Lines, Line =/= <<>>].

lower_header(Line) ->
    case binary:split(Line, <<":">>) of
        [Name, Value] ->
            <<(string:lowercase(Name))/binary, ": ", (string:trim(Value))/binary>>;
        _ ->
            Line
    end.

reason(200) -> "OK";
reason(201) -> "Created";
reason(202) -> "Accepted";
reason(400) -> "Bad Request";
reason(404) -> "Not Found";
reason(409) -> "Conflict";
reason(500) -> "Internal Server Error";
reason(_) -> "Error".
