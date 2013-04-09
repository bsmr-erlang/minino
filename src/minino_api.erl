%%%-------------------------------------------------------------------
%%% @author Pablo Vieytes <pvieytes@openshine.com>
%%% @copyright (C) 2013, Openshine s.l.
%%% @doc
%%%
%%% @end
%%% Created :  15 Mar 2013 by Pablo Vieytes <pvieytes@openshine.com>
%%%-------------------------------------------------------------------
-module(minino_api).
-include("include/minino.hrl").


-export([response/2,
	 path/1,
	 render_template/2,
	 build_url/3,
	 get_settings/1
	]).

-type template_path() :: string().
-type template_args() :: [{atom(), string()}].



response(Msg, MReq)->
    minino_req:response(Msg, MReq).

path(MReq) ->
    minino_req:path(MReq).


%% @doc render a template.
-spec render_template(template_path(), template_args()) -> {ok, string()} | {error, term()}.
render_template(Template, Args) ->
    minino_templates:render(Template, Args).



%% @doc build url.
-spec build_url(Id::atom(), Args::[{Key::atom(), Value::string()}], MReq::term()) -> 
		       {ok, string()} | {error, term()}.
build_url(Id, Args, MReq) ->
    F = MReq#mreq.build_url_fun,
    F(Id, Args).


%% @doc get minino settings.
-spec get_settings(Req::term()) -> [term()].
get_settings(MReq) ->
    MReq#mreq.mconf.
