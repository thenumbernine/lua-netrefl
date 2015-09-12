--[[
a remote player has a client object, instead of a server object
	(or maybe they'll have a limited server object?)
	
a local player will have a client object and a full-on server object

client objects do the rendering and input
--]]

local class = require 'ext.class'

local ClientConn = class()
function ClientConn:init() end
function ClientConn:update() end

return ClientConn
