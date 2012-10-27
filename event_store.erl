% namespaces this entire block of code
-module(event_store).
-define(SERVER, event_store).

% makes the functions that follow available externally
-export([start/0, process_loop/1, util_test/1, add_event_subscribers/2, get_subscribers/1, subscribers/2]).

% is included to allow compiling queries using qlc:q and evaluating them using qlc:e
-include_lib("stdlib/include/qlc.hrl").

% is that table definition for a table called event_subscribers with fields event_name and subscribers <List>
% Subscribers contains ClientPids of each subscriber.
-record(event_subscribers, {event_name, subscribers=[]}).

% =========================================================================
% Description:
% Starts the event_store process with a default parameter of true
% =========================================================================
start() ->
	erlang:register(?SERVER, spawn(event_store, process_loop, [true])).

% =========================================================================
% Description:
% The adds a ClientPid to the List of each Event
% The data structure would be as follows
% ------------------------------------------------------------
% event_name | subscribers
% ------------------------------------------------------------
% ruby       | <0.58.0>, <0.59.0>, <0.61.0>, <0.80.0>
% ------------------------------------------------------------
% java       | <0.58.0>, <0.59.0>
% -----------------------------------------------------------
% and so on...
% this method appends the clients Pid for each Event in the EventList <List>
% =========================================================================
add_event_subscribers(EventList, ClientPid) ->
	lists:foreach(fun(Event) -> 
		?SERVER ! {update_client_for_event, Event, ClientPid} end, EventList).



% =========================================================================
% Description:
% The subscribers functions are 2 recursive clauses that defined the behaviour
% when the recursion reaches a state where the first parameter is an empty list 
%  
%"subscribers([], SubscriberList) -> "
% says that when there are no more Events in the EventList return the SubscriberList
% after flattening and sorting it uniquely
%
% "subscribers([FirstEvent | EventList], SubscriberList) ->"
% Splits the EventList into two lists 1. FirstEvent <List> and EventList<List>
% First Event contains the first element of the list while EventList contains the
% remaining.
%
% The FirstEvent is then used to fetch all subscribers for it.
% The Subscribers are converted into a Set (ensures no duplicates and allows 
% for set operations).
% 
% For each scenario of events it finds the intersection of all Pids that follow 
% every Event. 
% It checks to see if a user subscribes to every event in the EventList  
% if so returns that set of users
% 
% =========================================================================
subscribers([], SubscriberList) -> 
	lists:usort(lists:flatten(SubscriberList));
subscribers([FirstEvent | EventList], SubscriberList) ->
	case get_subscribers(FirstEvent) of
		{ok, Subscribers} ->		
			SubscribersSet = sets:from_list(Subscribers),
			SubscriberListSet = sets:from_list(SubscriberList),
			case sets:size(SubscriberListSet) of 					
				0 ->
					%NewSubscribersList = lists:append(SubscriberList, Subscribers),
					%subscribers(EventList, NewSubscribersList);
					NewSubscribersList = lists:append(SubscriberList, Subscribers),
					subscribers(EventList,NewSubscribersList);
				_  ->
					CommonSubscribers = sets:to_list(sets:intersection(SubscribersSet, SubscriberListSet)),
					subscribers(EventList, CommonSubscribers)
			end;
		_ -> 
			subscribers(EventList, SubscriberList)
	end.

% =========================================================================
% Description 
% Gets subscribers for a single event by sending a message to the process loop
% which queries the database to get the list of subscribers.
%  
% =========================================================================
get_subscribers(Event) ->
	?SERVER ! {get_subscribers, Event, self()},
	receive
		{ok, Subscribers} ->
			{ok, Subscribers};
		{error, Status} ->
			{error, Status}
	end.

% =========================================================================
% Description 
% The first time the process_loop is called it initialize Mnesia to create 
% the schema and table. This is not repeated on each start.
%
% update_client_for_event
% --------------------------------------
% Updates the database event with the new subscriber ClientPid
% triggers a call to the utility function util_update_client_for_events where
% this operation is actually performed.
%
% get_subscribers
% ----------------------
%  returns a List of all subscribers for a given Event and sends a message 
% back to the calling process in the get_subscriber method.
% =========================================================================
process_loop(FirstTime) ->
	if 
		FirstTime == true ->
			initialize_store(),
			process_loop(false);
		true ->
			receive
				{update_client_for_event, Event, ClientPid} ->
					io:format("Received with ~p~p~n", [Event, ClientPid]),
					util_update_client_for_event(Event, ClientPid),
					process_loop(FirstTime);
				{get_subscribers, Event, FromPid} ->
					FromPid ! util_get_subscribers(Event),
					process_loop(FirstTime);
				stop -> 
					ok
			end
	end.


% Utility Functions
% =========================================================================
% Test Function 
% Ignore this. Its used to quickly test if the data is being updated accurately
%
% =========================================================================
util_test(Key) ->
	F = fun() ->
		Values = mnesia:read(event_subscribers, Key),
		Values
	end,
	{atomic, Data} = mnesia:transaction(F),
	io:format("Data values from ~p ", [Data]).


% ===========================================================================
% Description:
% Gets Subscribers for an Event
% 
% It queries the database based on the event name. The Database is of Set type
% this ensures we don't have clashes.
% "Query = qlc:q([X#event_subscribers.subscribers || X <- mnesia:table(event_subscribers),
%								X#event_subscribers.event_name =:= Event]),"
% 
% This compiles the query and the following line executes the result.
% "Result = qlc:e(Query),"
% 
%
% =============================================================================
util_get_subscribers(Event) ->
	F = fun() ->
			Query = qlc:q([X#event_subscribers.subscribers || X <- mnesia:table(event_subscribers),
								X#event_subscribers.event_name =:= Event]),
			Result = qlc:e(Query),
			Result
	end,	
	{atomic, Subscribers} = mnesia:transaction(F),
	FlattenSubscriberList = lists:flatten(Subscribers),
	{ok, FlattenSubscriberList}.

% ===========================================================================
% Description:
% Updates a client for an event
%  
% If a client subscribes to a new event its updated in the event_store table
% with the clients pid.
%
% =============================================================================
util_update_client_for_event(Event, ClientPid) ->
	F = fun() ->
		case mnesia:read(event_subscribers, Event) of
			[] -> 
				io:format("No Event found"),
				NewEvent = #event_subscribers{event_name=Event, subscribers=[ClientPid]},
				mnesia:write(NewEvent);
			[E] ->
				io:format("Event found"),
				mnesia:write(E#event_subscribers{subscribers = [ClientPid | E#event_subscribers.subscribers]})				
		end
	end,
	{Status, Data} =mnesia:transaction(F),	
	io:format("Transaction Status and data ~p ~p", [Status, Data]).


% ===========================================================================
% Description:
% Initializes the event_store in the database.
% Ensures that the schema is loaded on the current node.
%  
% Starts mnesia and initializes the table creation process
%
% =============================================================================
initialize_store() ->
	mnesia:create_schema([node()]),
	mnesia:start(),
	initialize_event_store().
	
% ===========================================================================
% Description:
% Checks if a table of the name event_subscribers already exists by 
% querying to check the table type (which is a set in our case).
%  
% If no table is found (an exception is thrown which is handled with the table
% creation logic)
%
% The create table fetchs the attributes from the record definition at the top
% of the page. 
% We use disc_copies so that in case mnesia crashes the information isnt lost.
% However it remains fast as the information is also always loaded in memory.
% 
% The disc_copies are loaded only in the current node.
% =============================================================================
initialize_event_store() ->
	try 
		mnesia:table_info(event_subscribers, type)
	catch
		exit:_ ->
			mnesia:create_table(event_subscribers, [{attributes, record_info(fields, event_subscribers)}, {type, set}, {disc_copies, [node()]}])
	end.
