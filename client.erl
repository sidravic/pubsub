% namespaces this entire block of code
-module(client).
% makes the functions that follow available externally
-export([start/1, subscribe/2, process_loop/0]).

% ==================================================================
% Description
% starts the feed client which in turn starts the message broker 
% which in turn starts the event store :)
%
% It spawns a new process "process_loop" which will act as the 
% run loop to carry out all the processing for the client.This 
% process_loop is an infinite loop run using tail recursion.
% 
% The sigin process allows the messagebroker to keep track of the
% users client process ID so that it can send it feed messages when
% they arrive.
%
% Parameters
% Nickname <Atom>
% ==================================================================

start(Nickname) ->	
	Pid = spawn(?MODULE, process_loop, []),
	message_broker:start(),
	message_broker:signin(Nickname, Pid).


% ==================================================================
% Description: 
% Once the server is running the subscribe method interface will
% allow a user with a Nickname to subscribe to new Event titles 
% like ruby, messaging, twitter. The nickname is the unique id 
% like twitter 
%
% Parameters:
% Nickname: <Atom>
% EventList: <List> Ex: [ruby, python, "gophers", "coffee"] 
% ==================================================================

subscribe(Nickname, EventList) ->
	message_broker:subscribe(Nickname, EventList).
	

% ==================================================================
% Description:
% Gets spawned as an independent process at the start.
% Runs as an infinite loop and can accept message when 
% sent by the message_broker process using this syntax 

% Pid ! {someatom, Variable}
% When a feed message arrives it prints out this message
% ==================================================================
process_loop() ->
	receive		
		{feed, Message} ->
			io:format("Feed Message: ~p", [Message]),
			process_loop();
		stop ->
			ok
	end.
	


	