-module(semaphore_tests).

-include_lib("eunit/include/eunit.hrl").

-export([conforming_fun/0,
         nonconforming_fun/0,
         crashing_fun/0
        ]).

-define(SEM_NAME, semtest).
-define(SEM_VAL, 2).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% Helper functions
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec conforming_fun() -> ok.

conforming_fun() ->
    case semaphore:timed_wait(?SEM_NAME, 5000) of
        ok ->
            timer:sleep(2000),
            semaphore:post(?SEM_NAME);
        {error, timeout} ->
            timeout
    end.

-spec nonconforming_fun() -> ok.

nonconforming_fun() ->
    case semaphore:timed_wait(?SEM_NAME, 5000) of
        ok ->
            timer:sleep(2000),
            % No call to semaphore:post/1
            % Function terminates normally
            ok;
        {error, timeout} ->
            timeout
    end.

-spec crashing_fun() -> no_return().

crashing_fun() ->
    case semaphore:timed_wait(?SEM_NAME, 5000) of
        ok ->
            timer:sleep(2000),
            % No call to semaphore:post/1
            % Function crashes
            throw(boom);
        {error, timeout} ->
            timeout
    end.

-spec count_elements(List::list(Type)) -> list({Key::Type, Count::pos_integer()}).

count_elements(List) ->
    Fun = fun(Elem, AccIn) ->
        orddict:update_counter(Elem, 1, AccIn)
    end,
    Dict = lists:foldl(Fun, orddict:new(), List),
    orddict:to_list(Dict).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

setup_test() ->
    ?assertMatch({ok, _}, semaphore:start_link(?SEM_NAME, ?SEM_VAL)).

get_value_test() ->
    ?assertEqual(?SEM_VAL, semaphore:get_value(?SEM_NAME)).

post_when_not_allowed_test() ->
    ?assertEqual(error, semaphore:post(?SEM_NAME)).

post_when_allowed_test() ->
    ?assertEqual(2, semaphore:get_value(?SEM_NAME)),
    ?assertEqual(ok, semaphore:try_wait(?SEM_NAME)),
    ?assertEqual(1, semaphore:get_value(?SEM_NAME)),
    ?assertEqual(ok, semaphore:try_wait(?SEM_NAME)),
    ?assertEqual(0, semaphore:get_value(?SEM_NAME)),
    ?assertEqual(error, semaphore:try_wait(?SEM_NAME)),
    ?assertEqual(ok, semaphore:post(?SEM_NAME)),
    ?assertEqual(ok, semaphore:post(?SEM_NAME)),
    ?assertEqual(error, semaphore:post(?SEM_NAME)).


concurrent_access_conforming_test_() ->
    {timeout, 10000, [fun () ->

     ?assertEqual(?SEM_VAL, semaphore:get_value(?SEM_NAME)),
     ?assertEqual([{ok, 6}, {timeout, 4}],
                  count_elements(rpc:parallel_eval(lists:duplicate(10, {?MODULE, conforming_fun, []})))),
     ?assertEqual(?SEM_VAL, semaphore:get_value(?SEM_NAME))

    end]}.

concurrent_access_nonconforming_test_() ->
    {timeout, 10000, [fun () ->

     ?assertEqual(?SEM_VAL, semaphore:get_value(?SEM_NAME)),
      ?assertEqual([{ok, 6}, {timeout, 4}],
                   count_elements(rpc:parallel_eval(lists:duplicate(10, {?MODULE, nonconforming_fun, []})))),
     ?assertEqual(?SEM_VAL, semaphore:get_value(?SEM_NAME))

    end]}.

concurrent_access_crashing_test_() ->
    {timeout, 10000, [fun () ->

     ?assertEqual(?SEM_VAL, semaphore:get_value(?SEM_NAME)),
     ?assertEqual([{boom, 6}, {timeout, 4}],
                  count_elements(rpc:parallel_eval(lists:duplicate(10, {?MODULE, crashing_fun, []})))),
     ?assertEqual(?SEM_VAL, semaphore:get_value(?SEM_NAME))
     
    end]}.

teardown_test() ->
    ok.

