-type maxchilds() :: pos_integer().
-type maxnumberinchain() :: 'infinity' | pos_integer().

-record(bstate, {
        free_proc = []      :: [] | [pid()],                          % free processes
        a_slots = 0         :: pos_integer(),                         % avialiable slots
        range = {0,0}       :: {non_neg_integer(),non_neg_integer()}, % randge for calculating
        max_chain = 0       :: non_neg_integer(),                     % max current chain
        in_work = 0         :: non_neg_integer(),                     % still in work
        reply_to            :: 'undefined' | pid(),
        parent              :: pid()
    }).

-type bstate() :: #bstate{}.
