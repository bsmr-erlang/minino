%%%-------------------------------------------------------------------
%%% Copyright (c) Openshine s.l.  and individual contributors.
%%% All rights reserved.
%%% 
%%% Redistribution and use in source and binary forms, with or without modification,
%%% are permitted provided that the following conditions are met:
%%% 
%%%     1. Redistributions of source code must retain the above copyright notice, 
%%%        this list of conditions and the following disclaimer.
%%%     
%%%     2. Redistributions in binary form must reproduce the above copyright 
%%%        notice, this list of conditions and the following disclaimer in the
%%%        documentation and/or other materials provided with the distribution.
%%% 
%%%     3. Neither the name of Minino nor the names of its contributors may be used
%%%        to endorse or promote products derived from this software without
%%%        specific prior written permission.
%%% 
%%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
%%% ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
%%% WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
%%% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
%%% ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
%%% (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
%%% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
%%% ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
%%% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
%%% SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%%% 
%%% @author Pablo Vieytes <pvieytes@openshine.com>
%%% @copyright (C) 2013, Openshine s.l.
%%% @doc
%%%
%%% @end
%%% Created :  10 Apr 2013 by Pablo Vieytes <pvieytes@openshine.com>
%%%-------------------------------------------------------------------

-module(minino_sessions).
-include("include/minino.hrl").

-behaviour(gen_server).

%% API
-export([start_link/1]).
-export([get_or_create/1,
	 get_cookies/1,
	 get_cookie/2,
	 set_cookie/3,
	 get_dict/1,
	 update_dict/2,
	 get_session_cookie_domain/0,
	 get_session_cookie_httponly/0,
	 get_session_cookie_path/0,
	 get_session_cookie_secure/0
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-define(DB, ?MODULE).

-define(PURGETIME, 60). %% db purge time in seconds.

-record(state, {session_time,
		secret_key,
		session_name,
		session_cookie_httponly,
		session_cookie_domain,
		session_cookie_path,
		session_cookie_secure
	       }).

-record(mreq_session, {new, key, modified}).
-record(stored_session, {key, dict, time}).



%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link(Params::[term()]) -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Params) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Params, []).


%% @doc get or create session.
-spec get_or_create(MReq::term()) -> {ok, Session::string(), MReq1::term()} | {error, Reason::term()}.
get_or_create(MReq) ->
    gen_server:call(?SERVER, {get_or_create_session, MReq}).


%% @doc get cookies.
-spec get_cookies(MReq::minino_req()) ->[{string(), string()}]|undefined.
get_cookies(MReq) ->
    CReq = MReq#mreq.creq,
    case cowboy_req:cookies(CReq) of
    	{undefined, _CReq} -> undefined;
    	{List, _CReq} ->
    	    [{binary_to_list(N), binary_to_list(V)} || {N,V} <- List]
    end.
    


%% @doc get cookie.
-spec get_cookie(MReq::minino_req(), CookieName::string()) -> string()|undefined.
get_cookie(MReq, CookieName) ->
    CReq = MReq#mreq.creq,
    CookieNameBin = list_to_binary(CookieName),
    case cowboy_req:cookie(CookieNameBin, CReq) of
    	{undefined, _CReq} -> undefined;
    	{Cookie, _CReq} -> binary_to_list(Cookie)
    end.
    

%% @doc set cookie.
-spec set_cookie(MReq::minino_req(), CookieName::string(), CookieVal::string()) -> 
			MReq1::minino_req() | {error, term()}.
set_cookie(MReq, CookieName, CookieVal) ->
    gen_server:call(?SERVER, {set_cookie, MReq, CookieName, CookieVal}).

%% @doc get minino session dict.
-spec get_dict(MReq::minino_req()) -> Dict::dict().
get_dict(MReq) ->
    gen_server:call(?SERVER, {get_dict, MReq}).

%% @doc update minino session dict.
-spec update_dict(MReq::minino_req(), Dict::dict()) -> 
				 {ok, MReq1::minino_req()} | {error, Error::term()}.
update_dict(MReq, Dict) ->
    gen_server:call(?SERVER, {update_dict, MReq, Dict}).

%% @doc get session cookie domain
-spec get_session_cookie_domain() -> string().
get_session_cookie_domain() ->
    gen_server:call(?SERVER, get_session_cookie_domain).

%% @doc get session cookie httponly
-spec get_session_cookie_httponly() ->  true | false.
get_session_cookie_httponly() ->
    gen_server:call(?SERVER, get_session_cookie_httponly).   

%% @doc get session cookie path
-spec get_session_cookie_path() ->  string().
get_session_cookie_path() ->
    gen_server:call(?SERVER, get_session_cookie_path).   

%% @doc get session cookie secure
-spec get_session_cookie_secure() ->  true | false.
get_session_cookie_secure() ->
    gen_server:call(?SERVER, get_session_cookie_secure).   


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
init([Mconf]) ->
    SessionTime = proplists:get_value(session_time, Mconf, ?DEFAULTSESSIONTIME),
    SecretKey = 
    	case proplists:get_value(secret_key, Mconf, error) of
    	    S when S /= error ->
    		S
    	end,
    SessionName = list_to_binary(
		    proplists:get_value(session_cookie_name, 
					Mconf, 
					?DEFAULTSESSIONNAME)), 
    HttpOnly = proplists:get_value(session_cookie_httponly, Mconf, true),
    SessionDomain =
	case proplists:get_value(session_cookie_domain, Mconf, none) of
	    SDomain when is_list(SDomain) ->
		list_to_binary(SDomain);
	    SDomain -> SDomain
	end,
    SessionPath =
	case proplists:get_value(session_cookie_path, Mconf, none) of
	    SPath when is_list(SPath) ->
		list_to_binary(SPath);
	    SPath -> SPath
	end,
    SessionSecure =  proplists:get_value(session_cookie_secure, Mconf, false),
    ask_purge_db(?PURGETIME),
    ets:new(?DB, [set, 
		  named_table,
		  {keypos, #stored_session.key}]),
    {ok, #state{session_time=SessionTime,
		secret_key=SecretKey,
		session_name=SessionName,
		session_cookie_httponly=HttpOnly,
		session_cookie_domain=SessionDomain,
		session_cookie_path=SessionPath,
		session_cookie_secure=SessionSecure
	       }}.

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
handle_call({set_cookie, MReq, CookieName, CookieVal}, _From, State) ->
    Reply =  server_set_cookie(MReq, CookieName, CookieVal, State),
    {reply, Reply, State};

handle_call({get_dict, Data}, _From, State) ->
    Reply =  get_dict_db(Data),
    {reply, Reply, State};

handle_call({update_dict, MReq, Dict}, _From, State) ->
    Reply =  update_dict_db(MReq, Dict),
    {reply, Reply, State};

handle_call({get_or_create_session, MReq}, _From, State) ->
    Reply =  get_or_create_session(MReq, State),
    {reply, Reply, State};

handle_call(get_session_cookie_httponly, _From, State) ->
    Reply = State#state.session_cookie_httponly,
    {reply, Reply, State};

handle_call(get_session_cookie_path, _From, State) ->
    Reply = State#state.session_cookie_path,
    {reply, Reply, State};

handle_call(get_session_cookie_secure, _From, State) ->
    Reply = State#state.session_cookie_secure,
    {reply, Reply, State};

handle_call(get_session_cookie_domain, _From, State) ->
    Reply = State#state.session_cookie_domain,
    {reply, Reply, State}.

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
handle_info(purge_db, State) ->
    purge_db(),
    ask_purge_db(?PURGETIME),
    {noreply, State};

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

get_or_create_session(MReq, State) ->
    CReq = MReq#mreq.creq,
    {BrowserSessionKey, CReq1} = cowboy_req:cookie(State#state.session_name, CReq),
    {MreqSession, CReq2} =
	case cowboy_req:path(CReq) of
	    {<<"/favicon.ico">>, _} -> 
		{#mreq_session{key=undefined, new=false}, CReq1};
	    {_Path, _Creq} ->
		StoredSes = get_session(BrowserSessionKey),
		case StoredSes of
		    undefined ->
			NewStoredSession = create_session(State),
			CowBoyCookieOps = create_cowboy_cookie_ops(State),
			Key = NewStoredSession#stored_session.key,
			NewCReq = 
			    cowboy_req:set_resp_cookie(
			      State#state.session_name, 
			      Key, 
			      CowBoyCookieOps, 
			      CReq1),
			MReqSes = 
			    #mreq_session{key=Key, 
					  new=true,
					  modified=true
					 },
			{MReqSes, NewCReq};
		    StoredSes ->
			Key = StoredSes#stored_session.key,
			MReqSes = 	 
			    #mreq_session{key=Key, 
					  new=false,
					  modified=false},
			
			{MReqSes, CReq1}
		end
	end,
    MReq1 = MReq#mreq{creq=CReq2,
		     session=MreqSession},
    {ok, MReq1}.

create_key(SecrectKey) ->
    Str = lists:flatten(io_lib:format("~p", [now()])),
    Md5 = erlang:md5(Str ++ SecrectKey),
    lists:flatten([io_lib:format("~2.16.0b", [B]) || <<B>> <= Md5]).



server_set_cookie(MReq, CookieName, CookieVal, State) ->
    CReq = MReq#mreq.creq,
    CookieName1 =
	case CookieName of
	    CookieName when is_list(CookieName) ->
		list_to_binary(CookieName);
	    CookieName -> CookieName
	end,
    CowBoyCookieOps = create_cowboy_cookie_ops(State),
    CReq1 = cowboy_req:set_resp_cookie(
    	      CookieName1, 
    	      CookieVal, 
	      CowBoyCookieOps,
	      CReq),
    MReq#mreq{creq=CReq1}.



get_session(undefined) ->
    undefined;

get_session(SessionKey) when is_binary(SessionKey) ->
    get_session(binary_to_list(SessionKey));

get_session(SessionKey) ->
    case ets:lookup(?DB, SessionKey) of
	[] -> undefined;
	[StoredSession] ->
	    Now = now_secs(),
	    case StoredSession#stored_session.time of
		Time when Time < Now -> 
		    Key = StoredSession#stored_session.key,
		    ets:delete(?DB, Key),
		    undefined;
		_E ->
		    StoredSession
	    end
    end.


    
create_session(State) ->
    SessionTime = State#state.session_time,
    Key = create_key(State#state.secret_key),
    Dict = dict:new(),
    Time = create_expired_time(SessionTime),
    StoredSession = #stored_session{key=Key, 
		       dict=Dict, 
		       time=Time},
    true = ets:insert(?DB, StoredSession),
    StoredSession.


create_expired_time(SessionTime) ->
    now_secs() + SessionTime.

now_secs() ->
    {Mega, Secs, _Mili} = now(),
    Mega*1000000 + Secs.

purge_db() ->
    Now =  now_secs(),
    Tuple = #stored_session{time='$1', _='_'},
    MatchSpec = [{Tuple,[{'=<','$1', Now}],[true]}],
    ets:select_delete(?DB, MatchSpec).

create_cowboy_cookie_ops(State)->
    HttpOnly = State#state.session_cookie_httponly,
    Ops = 
	[
	 {http_only, HttpOnly}
	],

    Ops1 = 
	case State#state.session_cookie_domain of
	    none -> Ops;
	    SessionDomain ->
		[{domain, SessionDomain}|Ops]
	end,
    Ops2 = case State#state.session_cookie_path of
	       none -> Ops1;
	       SessionPath ->
		   [{path, SessionPath}|Ops1]
	   end,
    case State#state.session_cookie_secure of
	true ->
	    [{secure, true}|Ops2];
	_Else -> Ops2
    end.



update_dict_db(MReq, Dict)->
    MReqSession = MReq#mreq.session,
    Key = MReqSession#mreq_session.key,
    case ets:lookup(?DB, Key) of
	[] -> {error, "session not found"};
	[StoredSes] -> 
	    NewStoredSession = StoredSes#stored_session{dict=Dict},
	    true = ets:insert(?DB, NewStoredSession),
	    NewMReqSes = MReqSession#mreq_session{new=false, modified=true},
	    {ok, NewMReqSes}
    end.

get_dict_db(MReq=#mreq{}) ->
    MReqSession = MReq#mreq.session,
    Key = MReqSession#mreq_session.key,
    get_dict_db(Key);

get_dict_db(Key) when is_list(Key) ->
    case ets:lookup(?DB, Key) of
	[] -> {error, "session not found"};
	[S] -> S#stored_session.dict
    end.

ask_purge_db(TimeSecs) ->
    erlang:send_after(TimeSecs*1000, self(), purge_db).
