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
                        application:ensure_all_started(?TESTAPP),
                        ?assertEqual(
                            {ok,[]},
                            application:ensure_all_started(?TESTAPP)
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
        fun start_app/0, % setup
        fun cleanup/1,   % cleanup
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
                        SupChild = supervisor:count_children(collatz_workers_sup),
                        ?assertEqual({workers, 0}, lists:keyfind(workers,1,SupChild)),
%                        collatz_batcher ! {batch, {1,1000}},
                        ?debugVal(lists:keyfind(workers,1,SupChild))
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
                            ?assertEqual(8, ?TM:calc_loop(17,3,0)),
                            ?assertEqual(10, ?TM:calc_loop(41,13,0)),
                            ?assertEqual(10, ?TM:calc_loop(40,13,0))
                    end
                }
            ]
        }
    }.

start_app() -> application:ensure_all_started(?TM).

cleanup(_) -> application:stop(?TM).

disable_output() ->
    error_logger:tty(false).
