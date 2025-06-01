-- TODO move this to netrefl when we move client(conn?), serverconn, and server

--[[
thoughts on remotecall ...
		- would have to know what client to use -- whether it was local or remote
		- would need to be initialized by having all remote calls registered with it
		  that would have to be done upon creation of each client, or each client class
		  which would mean providing the call information before creating/using any clients ...

		-- sooo we make one global netcall object:
		netcom = NetCom()

		-- and then we add all our calls to it in one place
		-- this would add a function to client.remotecall with the name "clientSetArmyDestPos"
		-- (the naming scheme prefix "client" means the client is asking the server, rather than the server requesting the client)
		netcom:addClientToServerCall{
			name = 'clientSetArmyDestPos',
			args = {
				-- this would have to be a specific reference to an army ... from a player ... from the server
				-- typical netencodes deep-traverse the object
				-- this would be the equivalent of a pointer-encode: a shallow-traversal/encoding of the reference to the object.
				-- note that encoding would include validation, as the function would, and any errors would be propagated back across the wire
				[1] = encodeArmyIndex,
				[2] = netfieldVec2OrNil,
			},
			-- you could also specify values to return once the function was done executing
			returnArgs = {
			},
			func = function(serverConn, army, pos)
				assert(table.find(serverConn.players, army.player), "tried to control an army we didn't own")
				if army.battle then return end	-- can't walk if we're in battle
				army.destPosWalking = v ~= nil
				if v then
					army.destPos = v
					army.angle = vec2.sub(army.destPos, army.pos):angle()
				end
			end,
		}

		-- and then, as we create clients, pass them the netcall object
		client1 = RemoteClientConn{netcom=netcom}
		client2 = LocalClientConn{netcom=netcom}

		-- and the client ctor subsequently initializes the respective netcom

		LocalClientConn:init()
			...
			if not LocalClientConn.call then
				LocalClientConn.call = {}
				for _,call in ipairs(args.netcall.calls) do
					-- build a .call[call.name] function for each netcall function that directly calls through
				end
			end

		RemoteClientConn:init()
			...
			if not RemoteClientConn.call then
				RemoteClientConn.call = {}
				... 
				-- build a .call[call.name] function for each netcall function that encodes, sends, and decodes args and calls arsg.done when done
			end
			

		-- upon subsequent call, the fields of clientSetArmyDestPos would be interpreted by the respective client.
		-- they would be encoded and decoded for remote clients, or simply passed for local clients.
		-- if an 'args.done' was provided, it would be called with

		self.conn:netcall{'clientSetArmyDestPos', self.selectedArmy, self.selectedArmy.pos + vec3(-rdx, -rdy, 0) * (3 * self.selectedArmy.speed)}
--]]

local table = require 'ext.table'	-- used with :encode
local class = require 'ext.class'
local assert = require 'ext.assert'
local Server = require 'netrefl.server'
local RemoteClientConn = require 'netrefl.remoteclientconn'

local NetCom = class()

--[[
calls are composed of objects with:
	name = call name
	preFunc = (optional) function to execute on this side of the wire before remote function execution ... maybe this should be the responsibility of caller to provide a wrapper?
	postFunc = (optional) function to execute on this side of the wire after remote function executes
	func = function to execute on the other side of the wire
	args = meta information describing the args.
		this information can take the form of a netfield with __netencode(value) returning a string and __netparse(parser) returning a value
		or a similar connEncode(client/server conn, value) and connParser(client/server conn, parser) if connection scope is necessary
		(I'm not condoning lambda functions for closure for the sake of enclosing client/server conn variables
			because the whole idea of these tables is to code up one call directory for use of many conn objects)
	returnArgs = meta info on the args
	useDone = set to true if the func() will be manually calling 'done' itself.  in such a case 'done' is passed as the last arg
--]]
function NetCom:init()
	self.clientToServerCalls = {}
	self.serverToClientCalls = {}
	self.clientToServerObjects = {}
	self.serverToClientObjects = {}
end

--[[
starting a game ...
args:
	addr = (optional) address to connect to
	port = port to connect to / listen on
	testingRemote = enable to test remote connections
	onConnect(clientConn) = function to call once a successful connection has been established
	threads = (optional) thread manager to pass to server
returns:
	clientConn, nil, remoteClientConn		-- for remote games (and the two objects match)
	clientConn, server, nil					-- for local games
	clientConn, server, remoteClientConn	-- for testingRemote games
--]]
function NetCom:start(args)
	local addr, port = args.addr, args.port
	local clientConn, server, remoteClientConn

	if not addr or args.testingRemote then
		server = Server{
			netcom = self,
			listenport = port,
			threads = args.threads,
		}
		serverConn = server:connectLocal(args.onConnect)
		assert(server)
		clientConn = serverConn.clientConn
	end
	
	if args.testingRemote then
		addr = server.socketaddr
		port = server.socketport
		server:update()
	end

	if addr or args.testingRemote then
		remoteClientConn = RemoteClientConn{
			netcom = self,
			threads = args.threads,
		}
		remoteClientConn:connect{
			addr = addr,
			port = port,
			success = function(clconn)
				-- THIS ISN'T GETTING ASSIGNED OR RETURNED ...		
				clientConn = clconn
				if args.onConnect then args.onConnect(clconn) end
			end
		}
	end
	
	-- hmm ... will this overlap with anything else in netcom?
	self.clientConn = clientConn
	self.remoteClientConn = remoteClientConn
	self.server = server
	
	return clientConn, server, remoteClientConn
end

function NetCom:update()
	if self.server then
		-- this looks for new conns
		-- it also updates local svconn
		-- which in turn updates localClientConn
		self.server:update()
	end
	if self.remoteClientConn then
		if self.remoteClientConn then
			self.remoteClientConn:update()
		elseif not self.remoteClientConn.connecting then
			print('got dropped!')
			self.remoteClientConn = nil
			-- and reshow the window?
		end
	end
end

--[[
self is NetCom
args:
	name = function name
	func = function to call after encode/decode of args
	preFunc = (optional) pre-call local side of wire
	postFunc = (optional) post-call local side of wire
	args = function argument encode/decode information
	returnArgs = (optional) function return value encode/decode information
	useDone = whether func calls done() itself
--]]
function NetCom:addCallForDir(field, callArgs)
	local name = assert.index(callArgs, 'name')
	if self[field][name] then
		error("tried to add the same command twice: "..field.." "..name)
	end
	self[field][name] = {
		name = name,
		preFunc = callArgs.preFunc,
		postFunc = callArgs.postFunc,
		func = assert(callArgs.func),
		args = callArgs.args or {},
		returnArgs = callArgs.returnArgs or {},
		useDone = not not callArgs.useDone,
	}
end

function NetCom:addClientToServerCall(args)
	self:addCallForDir('clientToServerCalls', args)
end

function NetCom:addServerToClientCall(args)
	self:addCallForDir('serverToClientCalls', args)
end

function NetCom:addObjectForDir(field, objArgs)
	local name = assert.index(objArgs, 'name')
	self[field][name] = {
		name = name,
		object = assert.index(objArgs, 'object'),
	}
end

function NetCom:addObject(args)
	self:addObjectForDir('serverToClientObjects', args)
	self:addObjectForDir('clientToServerObjects', args)
end

-- below are all helper static functions
-- to be used by ClientConn and ServerConn
-- so consider putting them somewhere else


--[[
helper function for encoding to send across the wire

conn = the conn object that might need to be passed to subsequent encode calls
name = function name
callArgs = a call's args or returnArgs
args = the values associated with the call's args/returnArgs
returns a string to be sent across the wire
--]]
function NetCom:encode(conn, name, callArgs, args)
	local s = table()
	s:insert(name)
	for i,callArg in ipairs(callArgs) do
		if callArg.__netencode then
			s:insert(callArg.__netencode(args[i]))
		elseif callArg.connEncode then
			s:insert(callArg.connEncode(conn, args[i]))
		else
			error("don't know how to encode param "..i.." of function "..name)
		end
	end
	return s:concat(' ')
end

--[[
another helper function
static (just like above) so consider replacing : with .

parser = word parser
conn = conn object for decoding
name = function name
callArgs = call's args or returnArgs
returns an array of values to be used for args
--]]
function NetCom:decode(parser, conn, name, callArgs)
	local args = {}
--DEBUG:print("NetCom:decode", parser, conn, name, callArgs)	
	for i,callArg in ipairs(callArgs) do
		if callArg.__netparse then
--DEBUG:print("NetCom:decode arg["..i.."] using __netparse")	
			args[i] = callArg.__netparse(parser)
		elseif callArg.connParse then
--DEBUG:print("NetCom:decode arg["..i.."] using connParse")	
			args[i] = callArg.connParse(conn, parser)
		else
			error("don't know how to decode param "..i.." of function "..name)
		end
--DEBUG:print("NetCom:decode arg["..i.."] = ", args[i])	
	end
	return args
end

--[[
static, so consider replacing : with .

conn = client/server connection
otherConn = server/client connection associated with it
directory = a NetCom's .clientToServerCalls' or .serverToClientCalls list
args:
	1st = function name
	rest = function args
	done = callback to call upon response with the function results passed as arguments
--]]
function NetCom:netcall_local(conn, otherConn, directory, args)
	local name = table.remove(args, 1)
	local call = assert(directory[name], "couldn't find xfer function "..name)
	if call.preFunc then
		call.preFunc(conn, table.unpack(args, 1, #call.args))
	end
	-- call the function directly, passing the clientconn first to identify where the call came from
	-- if .useDone is set then the called function is responsible for calling 'done' in the end (and is assumed to returned nothing)
	if call.useDone then
		args[#call.args + 1] = function(...)
			if args.done then
				args.done(...)
			end
			if call.postFunc then
				call.postFunc(conn, table.unpack(args, 1, #call.args))
			end
		end
		call.func(otherConn, table.unpack(args, 1, #call.args + 1))
	else
		local returnArgs = {call.func(otherConn, table.unpack(args, 1, #call.args))}
		if args.done then
			args.done(table.unpack(returnArgs, 1, #call.returnArgs))
		end
		if call.postFunc then
			for i=1,#call.returnArgs do
				args[#call.args + i] = returnArgs[i]
			end
			call.postFunc(conn, table.unpack(args, 1, #call.args + #call.returnArgs))
		end
	end
end

return NetCom
