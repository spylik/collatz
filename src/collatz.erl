%% --------------------------------------------------------------------------------
%% File:    collatz.erl
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

-module(collatz).

% supervisor is here
-behaviour(supervisor).

-include("collatz.hrl").

%% API
-export([
        start_root_sup/1,
        start_workers_sup/0,
        init/1
    ]).

%%%%%%%%%%%%%%%%%%%%%%%%% temporary
-compile(export_all).
-include("deps/teaser/include/utils.hrl").
%%%%%%%%%%%%%%%%%%%%%%%%% end of temorary

-define(SERVER, ?MODULE).
-define(WorkerSup, collatz_workers_sup).
-define(TimeOut, 50).

% @doc start root supervisor
-spec start_root_sup(MaxChilds) -> Result when
    MaxChilds :: maxchilds(),
    Result :: supervisor:startlink_ret().

start_root_sup(MaxChilds) ->
    supervisor:start_link({local, collatz_sup}, ?MODULE, [root, MaxChilds]).

% @doc start workers supervisor
-spec start_workers_sup() -> Result when
    Result :: supervisor:startlink_ret().

start_workers_sup() ->
    supervisor:start_link({local, ?WorkerSup}, ?MODULE, [workers]).

% @doc init callbacks
-spec init(Options) -> Result when
    Options :: ['workers'] | [maxchilds()],
    Result :: {ok, {SupFlags :: supervisor:sup_flags(), [ChildSpec :: supervisor:child_spec()]}}.

% Root supervisor init callback
init([root,_MaxChilds]) ->
    RestartStrategy = {rest_for_one,1,10}, 
    
    % batcher worker
%    Batcher = [
%        #{
%            id => collatz_batcher,
%            start => {?MODULE, start_batcher, [MaxChilds]},
%            restart => temporary,
%            shutdown => brutal_kill,
%            type => worker
%        }
%    ],
    
    % worker supervisor
    Workers = [
        #{
            id => collatz_workers_sup,
            start => {?MODULE, start_workers_sup, []},
            restart => permanent,
            shutdown => brutal_kill,
            type => supervisor
        }
    ],
    {ok, {RestartStrategy, lists:append([Workers])}};


% Workers supervisor init callback
init([workers]) ->
    RestartStrategy = {simple_one_for_one,1,10}, 
    Childrens = [
        #{
            id => collatz_worker,
            start => {?MODULE, start_worker, []},
            restart => temporary,
            shutdown => brutal_kill,
            type => worker
        }
    ],
    {ok, {RestartStrategy, Childrens}}.


% @doc start batcher callback
-spec start_batcher(Maxchilds) -> Result when
    Maxchilds :: maxchilds(),
    Result :: {ok, pid()}.

start_batcher(Maxchilds) ->
    Pid = proc_lib:spawn_link(?MODULE, batcher_loop, [init, Maxchilds, self()]),
    register(collatz_batcher, Pid),
    {ok, Pid}.

batcher_loop(init, Maxchilds, Parent) ->
    process_flag(trap_exit, true),
    batcher_loop(#bstate{a_slots = Maxchilds, parent = Parent}).

batcher_loop(#bstate{
        free_proc = FP, 
        a_slots = AS, 
        range = {Min,Max}, 
        max_chain = MChain,
        in_work = InWork,
        parent = Parent,
        reply_to = Reply} = State
    ) ->
        ?debug("inwork ~p",[InWork]),
        process_flag(trap_exit, true),
        NewState = 
            receive
                {result, Worker, Number, ChainLength} when Min<Max ->
                    Worker ! {calc, Min+1},
                    ?debug("Get result from worker ~p for number ~p and Min is ~p Max is ~p. ChainLength length is ~p",[Worker,Number,Min,Max,ChainLength]),
                    State#bstate{max_chain = max(MChain,ChainLength), range = {Min+1,Max}, in_work = InWork-1};

                {result, Worker, Number, ChainLength} ->
                    NewInWork = InWork-1,
                    MaxChain = max(MChain,ChainLength),
                    {NewAS,NewFP} = case NewInWork of
                        0 ->
                            lists:map(fun(Wrk) ->
                                Wrk ! stop
                            end, FP),
                            Reply ! {result, MaxChain},
                            {length(FP), []};
                        _ -> ?here, {AS+1, [Worker|FP]}
                    end,
                    ?debug("Get result from worker ~p for number ~p and Min=:=Max. ChainLength length is ~p",[Worker,Number,ChainLength]),
                    State#bstate{max_chain = max(MChain,ChainLength), a_slots = NewAS, free_proc = NewFP, in_work = NewInWork};

                {batch, {Mn, Mx}, _ReplyTo} when InWork =/= 0 ->
                    error_logger:warning_msg("WARNING: cannot not dispatch new job {~p,~p}.~n
                        Still have ~p numbers to calculate from previous batch {~p,~p}~n",[Mn,Mx,InWork,Min,Max]),
                    State;

                {batch, {Mn, Mx}, _ReplyTo} when Mx-Mn < -1 ->
                    error_logger:error_msg("ERROR: Number ~p must be lager than ~p or equal",[Mn,Mx]),
                    State;

                {batch, {Mn, Mx}, ReplyTo} when FP =:= [] andalso AS > 0 ->
                    Jobs = Mx-Mn+1,
                    WorkersToStart = min(AS, Jobs),
                    lists:map(
                        fun(Number) ->
                            {ok, Pid} = supervisor:start_child(whereis(?WorkerSup), [self()]),
                            monitor(process, Pid),
                            Pid ! {calc, Number}
                    end, lists:seq(Mn,WorkersToStart)),
                    ?debug("Got dispatch message {~p,~p}",[Mn, Mx]),
                    State#bstate{a_slots = AS-WorkersToStart, range = {Mn+WorkersToStart-1, Mx}, in_work = Jobs, reply_to = ReplyTo};

                {'DOWN', _, process, Worker, normal} ->
                    State#bstate{free_proc = lists:delete(Worker, FP), a_slots=AS+1};

                {'EXIT', Parent, Reason} ->
                    exit(Reason);

                {system, From, Request} ->
                    sys:handle_system_msg(Request, From, Parent, ?MODULE, [], {state, State});

                Msg -> 
                    error_logger:warning_msg("WARNING: get unexpected message ~p when state ~p",[Msg,State]),
                    State
            end,
        ?debug("state is ~p",[NewState]),
        batcher_loop(NewState).

% sys protocol callbacks
system_continue(_, _, {state, State}) ->
    State.
system_get_state(State) ->
    {ok, State}.
system_terminate(Reason, _, _, _) ->
    exit(Reason).
system_code_change(Misc, _, _, _) ->
    {ok, Misc}.


% @doc start worker callback
-spec start_worker(ReportTo) -> Result when
    ReportTo :: pid() | atom(),
    Result :: {ok, pid()}.

start_worker(ReportTo) ->
    Pid = spawn_link(
        fun Loop() -> 
            {Number,ChainLength} = receive 
                {calc, Num} ->
                    {Num,calc_loop(Num, 0)};
                stop -> exit(normal)
            after 
                ?TimeOut -> exit(normal)    % stop innactive workers
            end,
            ReportTo ! {result, self(), Number, ChainLength},
            Loop()
        end
    ),
    {ok, Pid}.

% @doc calculation loop
calc_loop(1, Length) -> Length+1;
calc_loop(Num, Length) when 
        Num rem 2 =:= 0 ->
    calc_loop(Num div 2, Length+1);
calc_loop(Num, Length) ->
    calc_loop(Num*3+1, Length+1).
