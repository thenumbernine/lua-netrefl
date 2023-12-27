local receiveBlocking = require 'netrefl.receiveblocking'
local class = require 'ext.class'
local table = require 'ext.table'
local LocalServerConn = require 'netrefl.localserverconn'
local RemoteServerConn = require 'netrefl.remoteserverconn'
--require 'netrefl.netfield'
local ThreadManager = require 'threadmanager'
local err, socket = pcall(require, 'socket')
if not err then socket = nil end
 
--[[
how the server, clientconns, and serverconns are updated:

		if server then
			server:update()
		end
		if clconn then
			if clconn then
				clconn:update()
			elseif not clconn.connecting then
				print('got dropped!')
				clconn = nil
			end
		end
		
so for servers + local connections, server:update() should udpate all the server's threads
... and all the serverconn threads ... and all the localserverconn's localclientconn threads.

but for remote connections, clconn:update() updates the threads
--]]

local Server = class()

--[[
args:
	netcom = NetCom
	listenport = (optional) listen port. default 12345
	threads = (optional) ThreadManager
--]]
function Server:init(args)
--DEBUG:print('Server:init', args)		
	self.netcom = assert(args.netcom)
	self.serverConns = table()
	self.threads = args.threads
	if not self.threads then
		self.threads = ThreadManager()
		self.ownThreads = true
	end
	
	if socket then -- init net listen
		self.socket = assert(socket.bind('localhost', args.listenport or 12345))
		self.socketaddr, self.socketport = self.socket:getsockname()
--DEBUG:print('Server:init socketaddr',self.socketaddr, 'socketport', self.socketport)
		self.socket:settimeout(0, 'b')
	end
end

function Server:update()

	if socket then -- listen for new connections
		local client = self.socket:accept()
		if client then
			self.threads:add(self.connectRemoteCoroutine, self, client)
		end
	end
	
	-- now handle connections
----DEBUG:print(require 'ext.timer'.getTime(), 'Server:update #serverConns', #self.serverConns)	
	for i=#self.serverConns,1,-1 do
		local serverConn = self.serverConns[i]
		if not serverConn:isActive() then
			if serverConn == self.localConn then
				self.localConn = nil
				print('DROPPING LOCAL CONNECTION!')
			end
			self.serverConns:remove(i)
		else
			if serverConn.update then
				serverConn:update()
			end
		end
	end
	
	if self.ownThreads then
		self.threads:update()
	end
end

-- create a local connection
function Server:connectLocal(onConnect)
	assert(not self.localConn, 'YOU ONLY GET ONE LOCAL CONNECTION')

	local serverConn = LocalServerConn(self)
	self.localConn = serverConn

	self.serverConns:insert(serverConn)
	onConnect(serverConn.clientConn)

	return serverConn
end

-- create a remote connection
function Server:connectRemoteCoroutine(client)
--DEBUG:print('Server:connectRemoteCoroutine', client)	
	local recv, reason = receiveBlocking(client, 10)
	if not recv then error("Server waiting for handshake receive failed with error "..tostring(reason)) end
	local expect = 'litagano'
	assert(recv == expect, "handshake failed.  expected "..expect..' but got '..tostring(recv))
--DEBUG:print('Server:connectRemoteCoroutine send motscoud')
	client:send('motscoud\n')

	local serverConn = RemoteServerConn(self, client)
	self.serverConns:insert(serverConn)
--DEBUG:print('Server:connectRemoteCoroutine returning', serverConn)
	return serverConn
end

-- helper function
function Server:netcall(args)
	for _,serverConn in ipairs(self.serverConns) do
		serverConn:netcall(table(args))
	end
end

return Server
