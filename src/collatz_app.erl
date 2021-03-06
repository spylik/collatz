%% --------------------------------------------------------------------------------
%% File:    collatz_app.erl
%% @author  Oleksii Semilietov <spylik@gmail.com>
%%
%% This file contain Erlang implementation for Collatz problem longest chain 
%% parallel computation.
%%
%% For more info, please refer to Readme:
%% https://github.com/spylik/collatz/blob/master/README.asciidoc
%% --------------------------------------------------------------------------------
-module(collatz_app).
-behaviour(application).

-export([
        start/2,
        stop/1
    ]).

% @doc start application and start cowboy listerner
-spec start(Type, Args) -> Result when
    Type :: application:start_type(),
    Args :: term(),
    Result :: {'ok', pid()} | {'ok', pid(), State :: term()} | {'error', Reason :: term()}.

start(_Type, _Args) ->
    collatz:start_root_sup(application:get_env(collatz, max_workers, 1000)).

% @doc stop application (we stopping cowboy listener here)
-spec stop(State) -> Result when
    State :: term(),
    Result :: ok.

stop(_State) ->
    ok.
