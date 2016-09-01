-module(collatz_tests).

-include_lib("eunit/include/eunit.hrl").
-include("collatz.hrl").
-define(TM, collatz).
-define(TESTAPP, collatz).

% --------------------------------- fixtures ----------------------------------
% tests for cover standart otp behaviour
otp_test_() ->
    {setup,
        fun disable_output/0, % setup
        {inorder,
            [  

                {<<"Application able to start via application:ensure_all_started()">>,
                    fun() ->
                        start_app(),
                        ?assertEqual(
                            {ok,[]},
                            start_app()
                        ),
                        App = application:which_applications(),
                        ?assert(is_tuple(lists:keyfind(?TESTAPP,1,App)))
                    end},
                {<<"Application able to stop via application:stop()">>,
                    fun() ->
                        application:stop(?TESTAPP),
                        App = application:which_applications(),
                        ?assertEqual(false, is_tuple(lists:keyfind(?TESTAPP,1,App)))
                end}
            ]
        }
    }.


batcher_sysproc_test_() ->
    {setup,
        fun disable_output/0, % setup
        {inorder,
            [
                {<<"Batcher able to start and register as collatz_batcher">>,
                    fun() ->
                        ?TM:start_batcher(3),
                        ?assert(is_pid(whereis(collatz_batcher)))
                    end
                },
                {<<"After start batcher must handle sys:get_state/1 and continue process">>,
                    fun() ->
                        {state, P1} = sys:get_state(whereis(collatz_batcher)),
                        ?assertEqual(3, P1#bstate.a_slots),
                        {state, P2} = sys:get_state(whereis(collatz_batcher)),
                        ?assertEqual(3, P2#bstate.a_slots)
                    end
                },
                {<<"Able to batch new task and start new worker">>,
                    fun() ->
                        {ok, _Pid} = ?TM:start_workers_sup(),
                        ?assert(is_pid(whereis(collatz_workers_sup))),
                        ?assertEqual({workers, 0}, lists:keyfind(workers,1,supervisor:count_children(collatz_workers_sup))),
                        collatz_batcher ! {batch, {1,10}, self()},
                        timer:sleep(10),
                        ?assertEqual({workers, 3}, lists:keyfind(workers,1,supervisor:count_children(collatz_workers_sup))),
                        Result = receive 
                            {result, Data} -> Data
                        after 50 -> false
                        end,
                        ?assertEqual(20, Result),
                        ?assertEqual({workers, 3}, lists:keyfind(workers,1,supervisor:count_children(collatz_workers_sup))),
                        collatz_batcher ! {batch, {3,8}, self()},
                        timer:sleep(10),
                        ?assertEqual({workers, 3}, lists:keyfind(workers,1,supervisor:count_children(collatz_workers_sup))),
                        Result2 = receive
                            {result, Data2} -> Data2
                        after 50 -> false
                        end,
                        ?assertEqual(20, Result2)

                    end
                }
            ]
        }
    }.

worker_supervisor_test_() ->
    {setup, 
        fun disable_output/0,
        {inorder, 
            [
                {<<"Worker supervisor able to start">>,
                    fun() ->
                        {ok, Pid} = ?TM:start_workers_sup(),
                        ?assert(is_pid(whereis(collatz_workers_sup))),
                        ?assertEqual(Pid, whereis(collatz_workers_sup))
                    end
                },
                {<<"Once supervisor started it must have 0 childs">>,
                    fun() ->
                        SupChild = supervisor:count_children(collatz_workers_sup),
                        ?assertEqual({workers, 0}, lists:keyfind(workers,1,SupChild))
                    end
                },
                {<<"Able to start supervisor child via call ">>,
                    fun() ->
                        supervisor:start_child(collatz_workers_sup, [self()]),
                        SupChild = supervisor:count_children(collatz_workers_sup),
                        ?assertEqual({workers, 1}, lists:keyfind(workers,1,SupChild)),
                        supervisor:start_child(collatz_workers_sup, [self()]),
                        supervisor:start_child(collatz_workers_sup, [self()]),
                        SupChild2 = supervisor:count_children(collatz_workers_sup),
                        ?assertEqual({workers, 3}, lists:keyfind(workers,1,SupChild2))
                    end
                },
                {<<"Worker able to calculate collatz chain and send back to dispatcher">>,
                    fun() ->
                        {ok, Pid} = supervisor:start_child(collatz_workers_sup, [self()]),
                        Pid ! {calc, 3},
                        ChainLength = 
                        receive 
                            {result, Pid, 3, Data} -> Data
                        after 50 -> false
                        end,
                        ?assertEqual(8, ChainLength),
                        % after 100 ms innactive workers must die.
                        timer:sleep(50),
                        ?assertEqual(undefined, process_info(Pid))
                    end
                },
                {<<"Worker supervisor able to stop via sys:terminate/2">>,
                    fun() ->
                        ok = sys:terminate(collatz_workers_sup, normal),
                        timer:sleep(10),
                        ?assertEqual(false, is_pid(whereis(collatz_workers_sup)))
                    end
                }
            ]
        }
    }.

test6_simple_test_() ->
    {setup,
        fun disable_output/0, % disable output for ci
        {inparallel,
            [
                {<<"calc_loop/3 must work">>,
                    fun() ->
                            ?assertEqual(1, ?TM:calc_loop(1,0)),
                            ?assertEqual(2, ?TM:calc_loop(2,0)),
                            ?assertEqual(8, ?TM:calc_loop(3,0)),
                            ?assertEqual(3, ?TM:calc_loop(4,0)),
                            ?assertEqual(6, ?TM:calc_loop(5,0)),
                            ?assertEqual(9, ?TM:calc_loop(6,0)),
                            ?assertEqual(17, ?TM:calc_loop(7,0)),
                            ?assertEqual(4, ?TM:calc_loop(8,0)),
                            ?assertEqual(20, ?TM:calc_loop(9,0)),
                            ?assertEqual(10, ?TM:calc_loop(13,0))
                    end
                }
            ]
        }
    }.

start_app() -> application:ensure_all_started(?TESTAPP).

%cleanup(_) -> application:stop(?TESTAPP).

disable_output() ->
    error_logger:tty(false).
