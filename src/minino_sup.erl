%%%-------------------------------------------------------------------
%%% @author Pablo Vieytes <pvieytes@openshine.com>
%%% @copyright (C) 2013, Openshine s.l.
%%% @doc
%%%
%%% @end
%%% Created :  6 Mar 2013 by Pablo Vieytes <pvieytes@openshine.com>
%%%-------------------------------------------------------------------

-module(minino_sup).

-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link(MConf) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [MConf]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
 
init([MConf]) ->
    io:format("conf: ~p~n", [MConf]),
    {ok, { {one_for_one, 5, 10}, []} }.

