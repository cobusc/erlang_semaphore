-module(semaphore_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SEMAPHORE_NAME, semtest).

setup_test() ->
    ?assertMatch({ok, _}, semaphore:start_link(?SEMAPHORE_NAME, 1)).

teardown_test() ->
    ok.

