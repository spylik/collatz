%% --------------------------------------------------------------------------------
%% File:    collatz.erl
%% @author  Oleksii Semilietov <spylik@gmail.com>
%%
%% This file contain Erlang implementation for Collatz problem longest chain 
%% parallel computation.
%%
%% For more info, please refer to Readme:
%% https://github.com/spylik/collatz/blob/master/README.asciidoc
%% --------------------------------------------------------------------------------

-module(collatz).

-define(NOTEST, true).
-ifdef(TEST).
    -compile(export_all).
-endif.

% supervisor is here
-behaviour(supervisor).

-include("collatz.hrl").

%% API
-export([
        start_root_sup/1,
        start_workers_sup/0,
        init/1,
        syn_longest_chain/2,
        start_batcher/1,
        batcher_loop/2,
        batcher_loop/1,
        start_worker/1,
        system_continue/3,
        system_get_state/1,
        system_terminate/4
    ]).

-define(SERVER, ?MODULE).
-define(WorkerSup, collatz_workers_sup).
-define(Batcher, collatz_batcher).
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
init([root,MaxChilds]) ->
    RestartStrategy = {rest_for_one,1,10}, 
    
    % batcher worker
    Batcher = [
        #{
            id => ?Batcher,
            start => {?MODULE, start_batcher, [MaxChilds]},
            restart => temporary,
            shutdown => brutal_kill,
            type => worker
        }
    ],
    
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
    {ok, {RestartStrategy, lists:append([Batcher,Workers])}};


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
    Pid = proc_lib:spawn_link(?MODULE, batcher_loop, [Maxchilds, self()]),
    register(?Batcher, Pid),
    {ok, Pid}.

% @doc batcher loop init process (we set process_flag here and going to loop)
-spec batcher_loop(Maxchilds, Parent) -> no_return() when
    Maxchilds :: maxchilds(),
    Parent :: pid().

batcher_loop(Maxchilds, Parent) ->
    process_flag(trap_exit, true),
    _ = ?MODULE:batcher_loop(#bstate{a_slots = Maxchilds, parent = Parent}).

% @doc main batcher loop
-spec batcher_loop(bstate()) -> no_return().
batcher_loop(#bstate{
        free_proc = FP, 
        a_slots = AS, 
        range = {Min,Max}, 
        max_chain = MChain,
        in_work = InWork,
        parent = Parent,
        reply_to = Reply} = State
    ) ->
        process_flag(trap_exit, true),
        NewState = 
            receive
                {result, Worker, _Number, ChainLength} when Min<Max ->
                    Worker ! {calc, Min+1},
                    State#bstate{max_chain = max(MChain,ChainLength), range = {Min+1,Max}, in_work = InWork-1};

                {result, Worker, _Number, ChainLength} ->
                    NewInWork = InWork-1,
                    MaxChain = max(MChain,ChainLength),
                    {Rn, Mcn, Rpl} = case NewInWork of
                        0 ->
                            Reply ! {result, MaxChain},
                            {{0,0},0,undefined};
                        _ -> 
                            {{Min,Max},max(MChain,ChainLength),Reply}
                    end,
                    State#bstate{max_chain = Mcn, range = Rn, reply_to = Rpl, free_proc = [Worker|FP], in_work = NewInWork};

                {batch, {Mn, Mx}, _ReplyTo} when InWork =/= 0 ->
                    error_logger:warning_msg("WARNING: cannot not dispatch new job {~p,~p}.~n
                        Still have ~p numbers to calculate from previous batch {~p,~p}~n",[Mn,Mx,InWork,Min,Max]),
                    State;

                {batch, {Mn, Mx}, _ReplyTo} when Mx-Mn < -1 ->
                    error_logger:error_msg("ERROR: Number ~p must be lager than ~p or equal",[Mn,Mx]),
                    State;

                {batch, {Mn, Mx}, ReplyTo} when FP =:= [] andalso AS > 0 ->
                    F = fun Loop(W, N, N) -> W;
                            Loop(W, N, NM) ->
                                {ok, Pid} = supervisor:start_child(whereis(?WorkerSup), [self()]),
                                monitor(process, Pid),
                                Pid ! {calc, N},
                                Loop([Pid|W],N+1,NM)
                        end,

                    Jobs = Mx-Mn+1,
                    WorkersToStart = min(AS, Jobs),
                    NewMin = (Mn+WorkersToStart),
                    _NewFW = F([],Mn,NewMin),
                    State#bstate{a_slots = AS-WorkersToStart, range = {NewMin-1, Mx}, in_work = Jobs, reply_to = ReplyTo};
                
                {batch, {Mn, Mx}, ReplyTo} when FP =/= [] ->
                    F = fun Loop(W, N, N) -> W;
                            Loop([H|T],N,NM) ->
                                H ! {calc, N},
                                Loop(T,N+1,NM)
                        end,
                    Jobs = Mx-Mn+1,
                    WorkersToStart = min(length(FP), Jobs),
                    NewMin = Mn+WorkersToStart,
                    NewFW = F(FP,Mn,NewMin),
                    State#bstate{free_proc = NewFW, range = {NewMin-1, Mx}, in_work = Jobs, reply_to = ReplyTo};

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
        batcher_loop(NewState).

% @doc sys protocol callback: continue
-spec system_continue(term(), term(), {state, State}) -> Result when
    State :: bstate(),
    Result :: bstate().

system_continue(_, _, {state, State}) ->
    State.

% @doc sys protocol callback: get_state
-spec system_get_state(State) -> Result when
    State :: bstate(),
    Result :: {ok, bstate()}.

system_get_state(State) ->
    {ok, State}.

% @doc sys protocol callback: terminate
-spec system_terminate(term(), term(), term(), term()) -> no_return().

system_terminate(Reason, _, _, _) ->
    exit(Reason).

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

% @doc calculate longest chain
-spec syn_longest_chain(Min,Max) -> Result when
    Min :: pos_integer(),
    Max :: pos_integer(),
    Result :: pos_integer().

syn_longest_chain(Min,Max) ->
    ?Batcher ! {batch, {Min,Max}, self()},
    receive
        {result, Data} -> Data
    end.
