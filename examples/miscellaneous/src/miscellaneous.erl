%%minino application

-module(miscellaneous).

-record(state, {}).

-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).


%% minino funs
-export([init/1,
	 dispatch_rules/0,
	 add_children_to_main_sup/1
	]).

%% views
-export([home_view/3
	 ]).

%% minino funs

add_children_to_main_sup(_MConf) ->
    [
     ?CHILD(miscellaneous_server, worker)
    ].
    

init(_MConf) ->
    {ok, #state{}}.

dispatch_rules() ->
    [%% {Id::atom(), Path::[string()|atom()], view::atom()}
     {root_page, [], home_view}
    ].


%% views
home_view(MReq, _Args, _State) ->
    {ok, Html} = minino_api:render_template("home.html", [{text, "Meow!!"}]),
    minino_api:response(Html, MReq).

