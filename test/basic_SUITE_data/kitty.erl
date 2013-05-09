%%minino application

-module(kitty).

%% minino funs
-export([init/1,
	 dispatch_rules/0]).


%% views
-export([home_view/2,
	 internal_error_view/2,
	 check_module/0]).


%% minino funs

init(_MConf) ->
    ok.

dispatch_rules() ->
    [%% {Id::atom(), Path::[string()|atom()], view::atom()}
     {root_page, [], home_view},
     {home_page, ["home"], home_view},
     {internal_error_page, ["error500"], internal_error_view}
    ].

%% views

home_view(MReq, _Args) ->
    {ok, Html} = minino_api:render_template("home.html", [{text, "Meow!!"}]),
    io:format("dbg: method: ~p~n", [minino_api:get_method(MReq)]),
    minino_api:response(Html, MReq).

check_module()->
    ?MODULE.

internal_error_view(_MReq, _Args) ->
    erlang:error(deliberate_error).
