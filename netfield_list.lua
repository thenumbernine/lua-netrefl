--[[
these functions are for lists used in netcalls
there is already a netFieldList that is supposed to act like this, but it's used for reflected objects rather than method calls
TODO unify the two list objects - netcalls and netfields?
--]]

local function createNetFieldList(netfield)
	assert(netfield)
	return {
		__netencode = function(list)
			local s = table()
			s:insert(#list)
			for _,v in ipairs(list) do
				s:insert(netfield.__netencode(v))
			end
			return s:concat(' ')
		end,
		__netparse = function(parser)
			local list = table()
			local num = assert(tonumber(parser:next()))
			for i=1,num do
				list[i] = netfield.__netparse(parser)
			end
			return list
		end,
	}
end

local function createConnFieldList(connfield)
	assert(connfield)
	return {
		connEncode = function(conn, list)
			local s = table()
			s:insert(#list)
			for _,v in ipairs(list) do
				s:insert(connfield.connEncode(conn, v))
			end
			return s:concat(' ')
		end,
		connParse = function(conn, parser)
			local list = table()
			local num = assert(tonumber(parser:next()))
			for i=1,num do
				list[i] = connfield.connParse(conn, parser)
			end
			return list
		end,
	}
end

local class = require 'ext.class'
local function createFieldOrNil(netfield)
	assert(netfield)
	-- should createNetFieldList and createConnFieldList return classes?
	-- or should this?
	-- because their contents get passed here
	--local subclass = netfield:subclass()
	local subclass = class(netfield)
	subclass.__netencode = function(v)
		if v == nil then return 'false' end
		return 'true '..netfield.__netencode(v)
	end
	subclass.__netparse = function(parser)
		if parser:next() ~= 'true' then return nil end
		return netfield.__netparse(parser)
	end
	return subclass
end

return {
	createNetFieldList = createNetFieldList,
	createConnFieldList = createConnFieldList,
	createFieldOrNil = createFieldOrNil,
}
