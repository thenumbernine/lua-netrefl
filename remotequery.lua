local WordParser = require 'netrefl.wordparser'

-- I don't know where else to put this
-- somewhere shared by ServerConn and Client alike ...
local RemoteQuery = class()

function RemoteQuery:init()
	self.msgidcounter = 0x1eadbeef
	self.onreceive = {}
end

--[[
get a new unique msgid
used for uniquely identifying queued request messages waiting for responses
--]]
function RemoteQuery:msgid()
	self.msgidcounter = self.msgidcounter + 1
	return ('%x'):format(self.msgidcounter)
end


--[[
sends a message requesting a response
sock = the luasocket socket
msg = the message to send across the connection
done(parser) = function to execute once a response is received

message prefixes: 
> means sending a request
< means getting a response
--]]
function RemoteQuery:query(sock, done, msg)
	local prefix
	if done == nil then
		prefix = ''
	else
		assert(type(done) == 'function')	-- no accidental skips
		local m = self:msgid()
		self.onreceive[m] = done
		prefix = '>'..m..' '
	end
	sock:send(prefix..msg..'\n')
end

-- if the cmd starts with < then call this method
function RemoteQuery:processResponse(cmd, parser, callQueue)
	local m = cmd:sub(2)
	local onreceive = self.onreceive[m]
	if onreceive then
		self.onreceive[m] = nil
		if callQueue then
			-- store for execution later by the main loop, outside of any coroutines
			-- mind you here the parser is the same used for the message loop
			-- so make a new parser
			local newparser = WordParser()
			local newdata
			if parser.token then
				newdata = parser.token .. ' ' .. parser.data:sub(parser.pos)
			else
				newdata = parser.data:sub(parser.pos)
			end
			newparser:setstr(newdata)
			callQueue:insert{onreceive, newparser}
		else
			-- if we're processing it immediately then we don't need a new parser
			--  we're staying in the scope of the old
			onreceive(parser)
		end
	else
		print('got response '..m..' when we had no responder registered')
	end
end

return RemoteQuery
