local class = require 'ext.class'

local WordParser = class()

function WordParser:setstr(s)
	self.data = s
	self.pos = 1 
	self:next()
end

-- TODO - define this in :setstr() and setfenv it there? more func defs but less derefs (faster?)
function WordParser:next()
	local lasttoken = self.token
	if self.pos > #self.data+1 then
		self.token = nil
	else
		local seppos = self.data:find(' ', self.pos) or (#self.data + 1)
		self.token = self.data:sub(self.pos, seppos-1)
		self.pos = seppos + 1
	end
	return lasttoken
end

function WordParser:expect(token)
	if self.token ~= token then
		print('expected '..token..' but got '..tostring(self.token))
		return false
	end
	self:next()
	return true
end

function WordParser:rest()
	return self.token .. ' '.. self.data:sub(self.pos)
end

return WordParser
