local class = require 'ext.class'
local ClientConn = require 'netrefl.clientconn'

local LocalClientConn = class(ClientConn)

function LocalClientConn:init(localServerConn, server)
	LocalClientConn.super.init(self)
	
	-- where we pass our messages to, in being like the remote copy
	self.serverConn = localServerConn
	
	-- what the server and every client can see
	-- for remote conn this will be an object net-sync'd to what the ***Client needs to see
	self.server = server
end

-- messages from clientside to serverside

function LocalClientConn:netcall(args)
	local netcom = self.server.netcom
	netcom:netcall_local(self, self.serverConn, netcom.clientToServerCalls, args)
end

return LocalClientConn
