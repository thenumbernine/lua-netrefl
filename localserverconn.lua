local class = require 'ext.class'
require 'netrefl.netfield'
require 'netrefl.netfield_vec'
local ServerConn = require 'netrefl.serverconn'
local LocalClientConn = require 'netrefl.localclientconn'


-- messages from clientside to serverside

local LocalServerConn = class(ServerConn)

function LocalServerConn:init(server)
	LocalServerConn.super.init(self, server)

	self.clientConn = LocalClientConn(self, self.server)
end

function LocalServerConn:isActive()
	return true		-- TODO - end condition?
end

-- was a thread of its own before
-- but it calls RemoteClientConn:update, which does menu stuff, which cannot be called from coroutines
function LocalServerConn:update()
	self.clientConn:update()
end


-- messages from the serverside to the clientside

function LocalServerConn:netcall(args)
	local netcom = self.server.netcom
	netcom:netcall_local(self, self.clientConn, netcom.serverToClientCalls, args)
end

return LocalServerConn
