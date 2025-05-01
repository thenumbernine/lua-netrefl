local err, socket = pcall(require, 'socket')
if not err then socket = nil end
local table = require 'ext.table'
local receiveBlocking = require 'netrefl.receiveblocking'
local WordParser = require 'netrefl.wordparser'
local RemoteQuery = require 'netrefl.remotequery'
local ThreadManager = require 'threadmanager'
local ClientConn = require 'netrefl.clientconn'
-- messages common to all subclasses

local netSendObj = require 'netrefl.netfield'.netSendObj
local netReceiveObj = require 'netrefl.netfield'.netReceiveObj

--[[
this is gonna do a lot of the work that Server does
in fact it'd be better described as a mirror of Server rather than a mirror of LocalClientConn

it and Server are both responsible for holding local data, like World and Stage
it and LocalClientConn are both responsible for message passing to their BattleClient and WorldClient's
--]]
local RemoteClientConn = ClientConn:subclass()

--[[
args:
	netcom = NetCom
	threads = (optional) thread manager

all client conns need a netcall object
local ones can get them from their server
--]]
function RemoteClientConn:init(args)
--DEBUG:print('RemoteClientConn:init', args)
	RemoteClientConn.super.init(self)

	self.netcom = assert(args.netcom)
	self.threads = args.threads
	if not self.threads then
		self.threads = ThreadManager()
		self.ownThreads = true
	end

	self.remoteQuery = RemoteQuery()
end

--[[
args:
	addr
	port
	fail (not yet used)
	success
--]]
function RemoteClientConn:connect(args)
--DEBUG:print('RemoteClientConn:connect addr',args.addr,'port',args.port)
	local sock, reason = socket.connect(args.addr, args.port)
	if not sock then
		print('failed to connect: '..tostring(reason))
		return false, reason
	end
	self.socket = sock
	sock:settimeout(0, 'b')
	self.connecting = true

	-- handshaking ...
	self.threads:add(function()
		sock:send('litagano\n')

		local expect = 'motscoud'
		local recv = receiveBlocking(sock, 10)
		if not recv then error("RemoteClientConn waiting for handshake failed with error "..tostring(reason)) end
		assert(recv == expect, "RemoteClientConn handshake failed.  expected "..expect..' but got '..tostring(recv))

		self.connecting = nil
		self.connected = true

		-- TODO - onfailure?  and a pcall please ... one the coroutines won't mind ...
		if args.success then args.success(self) end

		-- now spawn off a listening thread
		-- that will spend most its time blocking
		-- and will interpret messages for us
		self.listenThread = self.threads:add(self.listenCoroutine, self)
		self.sendThread = self.threads:add(self.sendCoroutine, self)
	end)
end

function RemoteClientConn:update()
	RemoteClientConn.super.update(self)

	if self.ownThreads then
		self.threads:update()
	end
end

-- 20kfps when walking around.  definitely not the bottleneck
--[[ clientlisten loop fps counter
local clientlistenTotalTime = 0
local clientlistenTotalFrames = 0
local clientlistenReportSecond = 0
--]]

-- coroutine
function RemoteClientConn:listenCoroutine()
--DEBUG:print('RemoteClientConn:listenCoroutine')
	coroutine.yield()

	local netcom = self.netcom

	local parser = WordParser()
	local result = {}

	while self.socket
	and self.socket:getsockname()
	do
		local reason
		data, reason = receiveBlocking(self.socket)
		if not data then
			if reason ~= 'timeout' then
				print('client remote connection failed: '..tostring(reason))
				return false
				-- TODO - die and go back to connection screen ... wherever that will be
			end
		else


--[[ clientlisten loop fps counter
			local clientlistenStart = getTime() / 1000
--]]

			repeat
--DEBUG:print("RemoteClientConn:listenCoroutine got data", data)
				parser:setstr(data)

				if #data > 0 then
					local cmd = parser:next()
					local m
					if cmd:sub(1,1) == '<' then		-- < means response.  > means request, means we'd have to reply ...
						self.remoteQuery:processResponse(cmd, parser)
					else

						-- requesting a response
						if cmd:sub(1,1) == '>' then
							m = cmd:sub(2)
							cmd = parser:next()
						end

						if cmd then
							local entry = netcom.serverToClientObjects[cmd]
							if entry then
--DEBUG:print('RemoteClientConn:listenCoroutine netcom.serverToClientObjects got object', cmd)
								netReceiveObj(parser, parser:next(), netcom.serverToClientObjects[cmd].object)
							else
								-- TODO this all parallels serverconn except ...
								-- * no waitFor() calls
								local call = netcom.serverToClientCalls[cmd]
								if call then
									local name = cmd
									local args = netcom:decode(parser, self, name, call.args)
									if call.useDone then
										args[#args + 1] = function(...)
											local ret = {...}
											if m then
												--waitFor(self, 'hasSentUpdate')
												local response = netcom:encode(self, name, call.returnArgs, ret)
												self.socket:send('<'..m..' '..response..'\n')
											end
										end
										call.func(self, table.unpack(args, 1, #call.args + 1))
									else
										local ret = {call.func(self, table.unpack(args, 1, #call.args))}
										if m then	-- looking for a response...
											--waitFor(self, 'hasSentUpdate')
											local response = netcom:encode(self, name, call.returnArgs, ret)
											self.socket:send('<'..m..' '..response..'\n')
										end
									end
								else
									print("RemoteClientConn listen got unknown command "..tostring(cmd).." of data "..data)
								end
							end
						end
					end
				end
				-- read as much as we want at once
				data = self.socket:receive('*l')
			until not data

--[[ clientlisten loop fps counter
			local clientlistenEnd = getTime() / 1000
			clientlistenTotalTime = clientlistenTotalTime + clientlistenEnd - clientlistenStart
			clientlistenTotalFrames = clientlistenTotalFrames + 1
			local thissec = math.floor(clientlistenEnd)
			if thissec ~= clientlistenReportSecond and clientlistenTotalTime > 0 then
				print('clientlistening at '..(clientlistenTotalFrames/clientlistenTotalTime)..' fps')
				clientlistenReportSecond = thissec
				clientlistenTotalTime = 0
				clientlistenTotalFrames = 0
			end
--]]

		end
	end
end

function RemoteClientConn:sendCoroutine()
--DEBUG:print('RemoteClientConn:sendCoroutine BEGIN')
	coroutine.yield()

	local netcom = self.netcom

	local objectLastStates = {}
	self.objectLastStates = objectLastStates
	for name,entry in pairs(netcom.clientToServerObjects) do
		objectLastStates[name] = {}
	end

	while self.socket
	and self.socket:getsockname()
	do
		for name,entry in pairs(netcom.clientToServerObjects) do
			netSendObj(self.socket, name, entry.object, objectLastStates[name])
		end

		self.hasSentUpdate = true

		coroutine.yield()
	end

--DEBUG:print('RemoteClientConn:sendCoroutine END')
end

--[[
args:
	1st = function name
	rest = function args
	done = callback to call upon response with the function results passed as arguments

RemoteServerConn is the same except
* clientToServerCalls is replaced with serverToClientCalls
* runs on a separate thread prefixed with a waitFor()
--]]
function RemoteClientConn:netcall(args)
	local netcom = self.netcom
	local name = table.remove(args, 1)
	local call = assert(netcom.clientToServerCalls[name], "couldn't find xfer function "..name)
	if call.preFunc then
		call.preFunc(self, table.unpack(args, 1, #call.args))
	end
	self.remoteQuery:query(
		self.socket,
		function(parser)
			local funcName = parser:next()
--DEBUG:assert(funcName == name, "expected "..tostring(name).." got "..tostring(funcName))
--DEBUG:print("RemoteClientConn:netcall query parser", parser.data)
--DEBUG:print("RemoteClientConn:netcall #call.returnArgs", #call.returnArgs)
			local returnArgs = netcom:decode(parser, self, name, call.returnArgs)
--DEBUG:print("RemoteClientConn:netcall returnArgs", table.unpack(returnArgs))
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
end

return RemoteClientConn
