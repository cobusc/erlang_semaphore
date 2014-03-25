-module(semaphore).

%%% Semaphore implementation based on POSIX semaphores.
%%%
%%% Acquisition:
%%%
%%% 1. wait: blocking acquisition
%%% 2. try_wait: non-blocking, returing error if acquisition failed
%%% 3. timed_wait: blocking acquisition with timeout
%%%
%%% Release:
%%%
%%% 1. post
%%% 2. Process termination.
%%%

-behaviour(gen_server).

%% API
-export([start_link/2,

         wait/1,
         try_wait/1,
         timed_wait/2,

         post/1
        ]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-type waiter() :: { WaitProcPid::pid(),
                    WaitProcMonRef::reference(),
                    CallingProcPid::pid()
                  }.

-type waiters() :: list(waiter()).

-type user() :: { UserProcPid::pid(),
                  UserProcMonRef::reference()
                }.

-type users() :: list(user()).


-record(state, 
{
    balance = 0 :: non_neg_integer(),
    waiters = [] :: waiters(), % Processes waiting to acquire the semaphore
    users = [] :: users()      % Processes using the semaphore
}).

-define(GLOBAL_NAME(X), {global, {?MODULE, X}}).

%%%===================================================================
%%% API
%%%===================================================================

%%
%% @doc Blocking semaphore acquisition
%%
%% Decrements (locks) the semaphore. If the semaphore's value is greater than zero, then the
%% decrement proceeds, and the function returns, immediately.  If the semaphore currently has the value zero, then the call
%% blocks until it becomes possible to perform the decrement (i.e., the semaphore value rises above zero).
%%
-spec wait(Name::atom()) -> ok.

wait(Name) ->
    timed_wait(Name, infinity).

%%
%% @doc Non-blocking semaphore acquisition
%%
%% Try to decrement the sempahore. If the decrement cannot be immediately performed, then call returns
%% an error instead of blocking.
%%
-spec try_wait(Name::atom()) -> ok | error.

try_wait(Name) ->
    gen_server:call(?GLOBAL_NAME(Name), try_wait, infinity).

%%
%% @doc Blocking semaphore acquisition with timeout
%%
%% Like wait/1, but with a limit on the amount of time that the call should block if the decrement cannot be immediately performed.
%%
-spec timed_wait(Name::atom(), Timeout::non_neg_integer()|infinity) -> ok | {error, timeout}.

timed_wait(Name, Timeout) ->
    gen_server:call(?GLOBAL_NAME(Name), {timed_wait, Timeout}, infinity).

%%
%% @doc Release semaphore
%%
-spec post(Name::atom()) -> ok | error.

post(Name) ->
    gen_server:call(?GLOBAL_NAME(Name), post, infinity).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Name, Balance) ->
    gen_server:start_link(?GLOBAL_NAME(Name), ?MODULE, Balance, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec init(Balance::pos_integer()) -> {ok, State::#state{}}.

init(Balance)
when is_integer(Balance), Balance>0 ->
    {ok, #state{balance = Balance}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(try_wait, _, #state{balance=0}=State) ->
    {reply, error, State};

handle_call(try_wait, {CallingPid, _}, #state{balance=Balance, users=Users}=State) ->
    MonRef = erlang:monitor(process, CallingPid),
    NewState = State#state{
        balance = Balance-1,
        users = [{CallingPid, MonRef} | Users]
    },
    {reply, ok, NewState};

handle_call({timed_wait, TimeoutMs}, {CallingPid, _}, #state{balance=0, waiters=Waiters}=State) ->
    %% Block until semaphore increases above 0
    Fun = 
    fun () ->
        true = erlang:link(CallingPid),
        Result =
        receive
            acquired -> ok
        after TimeoutMs ->
            {error, timeout}
        end,
        gen_server:reply(CallingPid, Result)
    end,

    {WaitingPid, WaitingMonRef} = spawn_monitor(Fun),
    NewState = State#state{waiters=[{WaitingPid, WaitingMonRef, CallingPid} | Waiters]},
    {noreply, NewState};

handle_call({timed_wait, _}, {CallingPid, _}, #state{balance=Balance, users=Users}=State) ->
    MonRef = erlang:monitor(process, CallingPid),
    NewState = State#state{
        balance = Balance-1, 
        users = [{CallingPid, MonRef} | Users]
    },
    {reply, ok, NewState};

handle_call(post, {CallingPid, _}, #state{balance=Balance, users=Users, waiters=Waiters}=State) ->
    % Only processes in the Users list can do a post
    case lists:keytake(CallingPid, 1, Users) of
        {value, {CallingPid, MonRef}, RemainingUsers} ->
            true = demonitor(MonRef, [flush]),
            % Notify waiting process OR increase balance
            case Waiters of
                [{WaitingProc, _WaitProcMon, CallingProc} | RemainingWaiters] -> % notify waiter
                    WaitingProc ! acquired,
                    NewUser = {CallingProc, erlang:monitor(process, CallingProc)},
                    {reply, ok, State#state{users=[NewUser | RemainingUsers], waiters=RemainingWaiters}};
                [] ->
                    {reply, ok, State#state{users=RemainingUsers, balance=Balance+1}}
            end;        
        false ->
            {reply, error, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, unknown, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({'DOWN', MonRef, process, Pid, _Info}, 
            #state{balance=Balance, users=Users, waiters=Waiters}=State) ->
    % We always remove the monitor
    true = demonitor(MonRef, [flush]),

    NewState = 
    case lists:keytake(MonRef, 2, Waiters) of
        {value, {Pid, MonRef}, RemainingWaiters} ->
            % Process not waiting anymore
            State#state{waiters=RemainingWaiters};
        false ->
            case lists:keytake(MonRef, 2, Users) of
                {value, {Pid, MonRef}, RemainingUsers} ->
                    % User process died without doing a POST. We need to bump the balance.
                    State#state{balance=Balance+1, users=RemainingUsers};
                false ->
                    % It is possible that the process associated with the monitor event
                    % was already removed from the Waiters list. In this case we 
                    % return the state as is.
                    State
            end
    end,
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
