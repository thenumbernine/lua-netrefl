--require 'netrefl.netfield'
--require 'netrefl.netfield_vec'
local table = require 'ext.table'
local receiveBlocking = require 'netrefl.receiveblocking'
local ServerConn = require 'netrefl.serverconn'
local WordParser = require 'netrefl.wordparser'
local RemoteQuery = require 'netrefl.remotequery'

local netSendObj = require 'netrefl.netfield'.netSendObj
local netReceiveObj = require 'netrefl.netfield'.netReceiveObj

local RemoteServerConn = ServerConn:subclass()

function RemoteServerConn:init(server, sock)
--DEBUG:print('RemoteServerConn:init', 	server, sock)
	RemoteServerConn.super.init(self, server)
	sock:setoption('keepalive', true)
	sock:settimeout(0, 'b')

	self.socket = sock
	
	self.remoteQuery = RemoteQuery()

	-- better define that in our instanciating classes
	self.listenThread = self.server.threads:add(self.listenCoroutine, self)
	self.sendThread = self.server.threads:add(self.sendCoroutine, self)
end

function RemoteServerConn:isActive()
	local active = coroutine.status(self.listenThread) ~= 'dead'
		and coroutine.status(self.sendThread) ~= 'dead'
----DEBUG:print('RemoteServerConn:isActive()', active)
	return active
end

local function waitFor(obj, field)
	obj[field] = nil
	repeat
		coroutine.yield()
	until obj[field]
end

-- messages from clientside to serverside

function RemoteServerConn:listenCoroutine()
--DEBUG:print('RemoteServerConn:listenCoroutine begin')
	local netcom = self.server.netcom
	
	coroutine.yield()
	
	local parser = WordParser()
	local result = {}

--DEBUG:print('self.server.socket:getsockname()', self.server.socket:getsockname())
--DEBUG:print('self.socket:getsockname()', self.socket:getsockname())
	while self.server
	and self.server.socket:getsockname()		-- while we're alive
	do	-- while we have a server, we're listening
					
		-- get the next line.  carriage return is my delimeter.  win.
		local data, reason = receiveBlocking(self.socket)
		if not data then
			if reason ~= 'timeout' then
				print('server remote connection failed: '..tostring(reason))
				break
			end
			-- if reason == 'timeout' then no big deal
		else
			repeat
			
				parser:setstr(data)
			
				local cmd = parser:next()
				
				if cmd:sub(1,1) == '<' then		-- we're getting a response
					self.remoteQuery:processResponse(cmd, parser)
				else
					local m
					if cmd:sub(1,1) == '>' then		-- the message we got wants a response
						m = cmd:sub(2)
						cmd = parser:next()
					end
					
					if cmd then
						local entry = netcom.clientToServerObjects[cmd]
						if entry then
							netReceiveObj(parser, parser:next(), netcom.clientToServerObjects[cmd].object)
						else

							-- try to handle it with the netcom
							local call = netcom.clientToServerCalls[cmd]
							if call then
								local name = cmd
								local args = netcom:decode(parser, self, name, call.args)
								-- TODO centric format for passing a 'done' callback to certain functions
								-- (currently only used for 'currentUnitMoveToTile')
								if call.useDone then
									args[#args + 1] = function(...)
										local ret = {...}
										if m then
											waitFor(self, 'hasSentUpdate')
											local response = netcom:encode(self, name, call.returnArgs, ret)
											self.socket:send('<'..m..' '..response..'\n')
										end									
									end
									call.func(self, table.unpack(args, 1, #call.args + 1))
								else
									local ret = {call.func(self, table.unpack(args, 1, #call.args))}
									if m then	-- looking for a response...
										waitFor(self, 'hasSentUpdate')
										local response = netcom:encode(self, name, call.returnArgs, ret)
										self.socket:send('<'..m..' '..response..'\n')
									end
								end
							else
								print('RemoteServerConn:listenCoroutine got an unknown message '..tostring(cmd))
							end
						end
					end
				end
				data = self.socket:receive('*l')
			until not data
		end
		
		coroutine.yield()
	end
end


-- messages from serverside to clientside

--[[ serversend loop fps counter
local serversendTotalTime = 0
local serversendTotalFrames = 0
local serversendReportSecond = 0
--]]

function RemoteServerConn:sendCoroutine()
--DEBUG:print('RemoteServerConn:sendCoroutine BEGIN')
	coroutine.yield()

	local netcom = self.server.netcom

	local objectLastStates = {}
	for name,entry in pairs(netcom.serverToClientObjects) do
--DEBUG:print('RemoteServerConn:sendCoroutine init objectLastStates', name, entry)
		objectLastStates[name] = {}
	end

	while self.server
	and self.server.socket:getsockname()		-- while we're alive
	do
--[[ serversend loop fps counter
		local serversendStart = getTime() / 1000
--]]

		for name,entry in pairs(netcom.serverToClientObjects) do
			netSendObj(self.socket, name, entry.object, objectLastStates[name])
		end
		
		-- used for some spin waits
		self.hasSentUpdate = true
		
--[[ serversend loop fps counter
		local serversendEnd = getTime() / 1000
		serversendTotalTime = serversendTotalTime + serversendEnd - serversendStart
		serversendTotalFrames = serversendTotalFrames + 1
		local thissec = math.floor(serversendEnd)
		if thissec ~= serversendReportSecond and serversendTotalTime > 0 then
			print('serversending at '..(serversendTotalFrames/serversendTotalTime)..' fps')
			serversendReportSecond = thissec
			serversendTotalTime = 0
			serversendTotalFrames = 0
		end
--]]
		
		coroutine.yield()
	end

--DEBUG:print('RemoteServerConn:sendCoroutine END')
end

function RemoteServerConn:netcall(args)
	self.server.threads:add(function()
		local netcom = self.server.netcom
		waitFor(self,'hasSentUpdate')
		local name = table.remove(args, 1)
		local call = assert(netcom.serverToClientCalls[name], "couldn't find xfer function "..tostring(name))
		if call.preFunc then
			call.preFunc(self, table.unpack(args, 1, #call.args))
		end
		self.remoteQuery:query(
			self.socket,
			function(parser)
				local returnArgs = netcom:decode(parser, self, name, call.returnArgs)
				-- TODO decode return args
				if args.done then
					args.done(table.unpack(returnArgs, 1, #call.returnArgs))
				end
				if call.postFunc then
					for i=1,#call.returnArgs do
						args[#call.args + i] = returnArgs[i]
					end
					call.postFunc(self, table.unpack(args, 1, #call.args + #call.returnArgs))
				end
			end,
			netcom:encode(self, name, call.args, args)
		)
	end)
end

return RemoteServerConn
