%% --------------------------------------------------------------------------------
%% File:    collatz_app.erl
%% @author  Oleksii Semilietov <spylik@gmail.com>
%%
%% @doc Task7:
%% Implement the task as an Erlang/OTP application each sequence is calculated 
%% by servers independently, a supervisor using an application’s setting 
%% "maximum number of workers” starts servers, collects results and finds the longest 
%% chain. 
%% 
%% The following iterative sequence is defined for the set of positive integers:
%% n → n/2 (n is even) n → 3n + 1 (n is odd)
%%
%% Using the rule above and starting with 13, we generate the following sequence:
%% 13 → 40 → 20 → 10 → 5 → 16 → 8 → 4 → 2 → 1
%%
%% It can be seen that this sequence (starting at 13 and finishing at 1) contains 10 terms.
%% Although it has not been proved yet (Collatz Problem), it is thought that all starting 
%% numbers finish at 1.
%%
%% Which starting number, under one million, produces the longest chain? 
%%
%% NOTE: Once the chain starts the terms are allowed to go above one million.
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
    collatz:start_root_sup(10).

% @doc stop application (we stopping cowboy listener here)
-spec stop(State) -> Result when
    State :: term(),
    Result :: ok.

stop(_State) ->
    ok.
