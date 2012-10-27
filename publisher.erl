-module(publisher)
-define(?SERVER, publisher).
-export([start/0]).


start() ->
	erlang:register(?SERVER, spawn(publisher, process_loop, [])).

% ===========================================================================
% Description:
% Published sends message to the message broker with the FeedKeys
%
% =============================================================================
process_loop() ->
	receive
		{publish_msg, Message, FeedKeys} ->
			message_broker:receive_published_msg(Message, FeedKeys),
			process_loop();
		stop ->
			ok
	end.
