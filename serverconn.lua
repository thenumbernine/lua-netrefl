--[[
players tell the battle how targetting works

server connections tell the server who is on what computer

they are split into the following:
	Loopback	-- at this very same computer. should have only 0 or 1 of these
	Remote		-- at another computer, probably across tcp/ip
	
loopback conns instanciate a loopback client, and the talking is done directly
remote conns just hold socket info for talking, and the remote computer has to make its own (global?) remote client
--]]


local class = require 'ext.class'
local table = require 'ext.table'

local ServerConn = class()

function ServerConn:init(server)
	self.server = server
	self.players = table()
	self.battles = table()
end

-- implement me per-child-class
function ServerConn:isActive() end

return ServerConn
