% namespaces this entire block of code
-module(message_broker).
% makes the functions that follow available externally
-export([start/0, signin/2, subscribe/2, process_loop/1, receive_published_msg/2]).
% defines a constant/macro which can referenced throughout this module. Cannot be reassigned.
-define(SERVER, message_broker).

% =========================================================================
% TODOs:
% 1. Unsubscribe from feed events
% 2. Sign out.
% The current implementation only focuses on creating a subscribing to feed 
% events and receiving those messages which are relevant to the subscription.
% =========================================================================

% =========================================================================
% Description:
% This is the core module that handles all the processing logic.
% 
% The Role of the broker is to identify if a newly arrived message is relevant
% to a user and route messages to the user.
% 
% Every Incoming message arrives with a feed Key like RabbitMQ topic exchanges
% and routes those messages based on the subscription topics
% 
% It starts a process loop and starts the event store. The process 
% accepts a parameter similar to a Hash to keep track of Nickname - ClientPid
% pairs
%% =========================================================================
start() ->
	erlang:register(?SERVER, spawn(message_broker, process_loop, [dict:new()])),
	event_store:start().
	
% =========================================================================
% Description:
% Sigin ensures the clientPid is updated and stored in the Dictionary.
% 
% This allows the broker to push messages when they are relevant to the client
% It sends  amessage to the broker run loop and waits for a reply instead being 
% a blocking call.  
% 
% The receive block waits for a response and then ends.
%% =========================================================================
signin(Nickname, ClientPid) ->
	?SERVER ! {signin, Nickname, ClientPid, self()},
	receive
		{ok, signed_in} ->
			{ok, signed_in};
		_ ->
			{error, could_not_signin}
	end.

% =========================================================================
% Description:
% Subscribes to an set of Events and waits for a response.
%  
% Parameters:
% Nickname <Atom>
% EventList <List>
%% =========================================================================

subscribe(Nickname, EventList) ->
	?SERVER ! {subscribe, Nickname, EventList, self()},
	receive
		{ok, subscribed} -> 
			{ok, subscribed};
		{ok, ignored} ->
			{ok, ignored}
	end.

% =========================================================================
% Description:
% Receives a message sent by the publisher process and receives FeedKeys and
% sends it to the process_loop.
%  
% Parameters:
% Message: <String/List>
% EventList <List> Ex: [ruby, gophers, warlocks]
%% =========================================================================
receive_published_msg(Message, FeedKey) ->
	?SERVER ! {published_msg, Message, FeedKey},
	{ok, published}.


% ============================================================================
% Description:
% Process Loop reacts to various types of messages and handles those accordingly
%
% signin
% --------------
% Checks if the Nickname, which is the key is present in the Dict, if so updates
% the ClientPid with the latest, just to ensure its upto date.
% 
% If not adds the Nickname to the Dict along with the Client Process ID.
% Calls the process_loop to continue with the tail recursion.% 
% The FromPid tells the process_loop to send the response to the waiting receive
% block of the sigin method.
%
% subscribe
% ---------------
% Identifies the ClientPid of the user who is subscribing to the new set of Events
% using the Dict.
% It then calls the event_store interface method with the EventList and the ClientPid.
% It returns {ok, subscribed} status when it finds a ClientPid else returns and ignored
% status
% Tail recursion continues.
%
% published_msg
% ----------------
% When a new message is published by the publisher this message is invoked.
% It accepts the published Message and FeedKeys <List>
%
% It sends a message to the event_store to fetch all subscribers for the given 
% events (FeedKeys) and event_store returns the ClientPids for each. This is 
% a unique set and messages are sent to each PID.
% 
% 
%% ==============================================================================
process_loop(UserClientPids) ->
	receive
		{signin, Nickname, ClientPid, FromPid} ->
			io:format("Data arrived ~p~p~p~n", [Nickname, ClientPid, FromPid]),
			NicknamePresent = dict:is_key(Nickname, UserClientPids),
			if
				NicknamePresent == true ->
					io:format("Data arrived Nick Present ~p~p~p~n", [Nickname, ClientPid, FromPid]),
					FromPid ! {ok, signed_in},
					process_loop(dict:update(Nickname, fun(_OldCliendPid) ->
											 ClientPid end, UserClientPids));					
				true ->
					io:format("Data arrived Nick Not present ~p~p~p~n", [Nickname, ClientPid, FromPid]),
					FromPid ! {ok, signed_in},
					process_loop(dict:store(Nickname, ClientPid, UserClientPids))					
			end;	
		{subscribe, Nickname, EventList, FromPid} ->
			case dict:find(Nickname, UserClientPids) of
				{ok, ClientPid} ->					
					event_store:add_event_subscribers(EventList, ClientPid),
					FromPid ! {ok, subscribed};					
				error ->
					FromPid ! {ok, ignored}
			end,
			process_loop(UserClientPids);
		{published_msg, Message, FeedKeys} ->			
			SubscribersList = event_store:subscribers(FeedKeys, []),
			lists:foreach(fun(SubscriberPid) ->
					SubscriberPid ! {feed, Message}
				end, SubscribersList),			
			process_loop(UserClientPids)
	end.

