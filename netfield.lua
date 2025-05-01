--[[

netfield format:
{
	-- string concat encode, string decode
	-- I'm thinking of cutting this out and forcing fields to state 'tostring' ...
	[fieldname] = true,

	-- string concat encode, function decode
	[fieldname] = function() ... end,

	-- explicit encode/decode functions
	[fieldname] = {
		__netencode=function(data) return a parsable string based on data end,
		__netparse=function(parser) return data based on parser:next()'s end,
		__netdiff=function(last,this) return true or false based on data end,
		__netcopy(this,last) return a copy of this, cached in last if it is non-null end,
	}

	...
}

TODO get rid of this and just have fieldnames (or map to an unimportant value like 1 or true)
and have the encode/decode built into the class type
or just do that up front, and have those matching method names be the ones that tables deref
(as they are "encode" and "decode" at the moment)

--]]

-- general escape/unescape for strings
-- escape delimiter
-- can't use \, that one's built into string escapes
-- can't use %, that one's built into pattern escapes
-- which is faster? multiple gsubs, or a single one with a callback?

local class = require 'ext.class'


local function netescape(s)
	return (s:gsub('%$','%$%$'):gsub(' ', '%$s'))
end

local function netunescape(s)
	return (s:gsub('%$s', ' '):gsub('%$%$', '%$'))
end



-- some useful functions ...

local function identity(x) return x end

-- TODO - AST, inlining, and regen and cache flattened functions
local function netSendObj(socket, prefix, thisObj, lastObj)
--DEBUG:print('netSendObj socket='..tostring(socket)..' prefix='..tostring(prefix)..' thisObj='..tostring(thisObj)..' lastObj='..tostring(lastObj))
	if not thisObj.__netfields then error("prefix '"..prefix.."' had no __netfields") end
	for fieldName, info in pairs(thisObj.__netfields) do
		if not info.__netsend then error("prefix='"..tostring(prefix).."' fieldName='"..tostring(fieldName).."' had no __netsend") end
--DEBUG:print('netSendObj', fieldName, info)
		info:__netsend(socket, prefix, fieldName, thisObj, lastObj, thisObj[fieldName])
	end
end

local function netReceiveObj(parser, field, obj)
	local info = obj.__netfields[field]

	-- we still have some object commands that don't apply to netfields
	-- TODO - map them all? and assert this? maybe? that might strain the encoder (skipping certain fields)
	if info == nil then
		print('ignoring field '..field..' for data '..parser.data)
		return
	end

	obj[field] = info.__netparse(parser, obj[field], obj)
	return true
end

-- default field
local NetField = class{
	-- utility functions:
	__netencode = tostring,
	__netparse = function(p) return p:next() end,
	__netdiff = require 'ext.op'.ne,
	__netcopy = identity,

	-- what brings it all together:
	__netsend = function(self, socket, prefix, field, thisObj, lastObj, thisValue)
		assert(lastObj)
		local lastValue = lastObj[field]
		if self.__netdiff(lastValue, thisValue) then
			lastObj[field] = self.__netcopy(thisValue, lastValue)		-- reuse if you can
			socket:send(prefix..' '..field..' '..self.__netencode(thisValue)..'\n')
		end
	end,
}


local NetFieldObject = class()

-- common __netsend for objects, especially members of arrays...
-- should this be a method of list, or of its members?  probably an allocator of its members?
function NetFieldObject.__netsend(self, socket, prefix, field, thisObj, lastObj, thisValue)
--DEBUG:print('NetFieldObject __netsend prefix='..prefix..' field='..field..' thisObj='..tostring(thisObj)..' lastObj='..tostring(lastObj)..' thisValue='..tostring(thisValue))
--DEBUG:assert(thisValue, "...thisValue is nil")
	local lastValue = lastObj[field]
	if not lastValue then
--DEBUG:print('...creating lastValue={}')
		lastValue = {}
		lastObj[field] = lastValue
	end
	assert(lastValue)
	netSendObj(socket, prefix..' '..field, thisValue, lastValue)
end

function NetFieldObject.__netparse(parser, lastValue, thisObj)
	assert(parser.token,
		"field expected a token but got "..tostring(parser.token)..
		" for data "..parser.data)

	local field = parser:next()
	assert(lastValue, "applying an obj field to an obj we haven't recieved yet\ndata:"..parser.data)

	if not netReceiveObj(parser, field, lastValue) then
		error('unable to parse field '..tostring(field)..' in line '..parser.data)
	end

	return lastValue
end


local netFieldBoolean = NetField:subclass()
netFieldBoolean.__netparse = function(p) return p:next() == 'true' end

local netFieldNumber = NetField:subclass()
netFieldNumber.__netencode = identity		-- concat as-is
netFieldNumber.__netparse = function(p)
	local data = p:next()
	local number = tonumber(data)
--DEBUG:print("netFieldNumber.__netparse p:next()="..tostring(data).." tonumber="..tostring(number))
	return number
end

local netFieldNumberOrNil = NetField:subclass()
netFieldNumberOrNil.__netencode = function(s)
	if s then return tostring(s) end
	return ''
end
netFieldNumberOrNil.__netparse = function(p)
	local s = p:next()
	if s ~= '' then return tonumber(s) end
end

local netFieldString = NetField:subclass()
netFieldString.__netencode = netescape		-- concat as-is
netFieldString.__netparse = function(p) return netunescape(p:next()) end		-- return the next token as-is

local netFieldStringOrNil = NetField:subclass()
netFieldStringOrNil.__netencode = function(s)
	if s then return netescape(s) end
	return ''
end
netFieldStringOrNil.__netparse = function(p)
	local s = p:next()
	if s ~= '' then return netunescape(s) end
end



-- t = table
-- n = how many
-- a = allocator function to fill extras
local function resizeArrayWithAllocator(t, n, a, ...)
	assert(t)
	local s = #t
	for i=n+1,s do t[i] = nil end
	for i=s+1,n do t[i] = a(...) end
end

local function resizeArrayWithValue(t, n, v)
	local s = #t
	for i=n+1,s do t[i] = nil end
	if v == nil then return end
	for i=s+1,n do t[i] = v end
end

-- define upfront the list type, like netFieldList(netFieldNumber)
-- that way the decoder knows what to expect.  the encoder could deduce it from the metatable no problem
local function netFieldList(netField)
	assert(netField)
	return {
		__netparse = function(parser, lastValue, thisObj)
			if not lastValue then
--DEBUG:print('netFieldList __netparse creating lastValue={}')
				lastValue = {}
			end
			if parser.token == '' then error('got here') end
			if parser.token == '#' then
				parser:next()
				if netField.__netallocator then
					resizeArrayWithAllocator(lastValue, tonumber(parser:next()), netField.__netallocator, thisObj)
				else
					resizeArrayWithValue(lastValue, tonumber(parser:next()), nil)
				end
			else
				local index = tonumber(parser:next())
				lastValue[index] = netField.__netparse(parser, lastValue[index], thisObj)
			end
			return lastValue
		end,

		-- DONE, now just add in a __netreceive and have it encapsulate __netparse
		__netsend = function(self, socket, prefix, field, thisObj, lastObj, thisValue)

			-- something in here is running twice as slow as the inline code in the unit send block ...
			-- even calling this and immediately returning still runs as fast

			local lastValue = lastObj[field]
			if not lastValue then
--DEBUG:print('netFieldList __netsend prefix='..prefix..' field='..field..' creating lastValue={}')
				lastValue = {}
				lastObj[field] = lastValue
			end

			if #thisValue ~= #lastValue then
				socket:send(prefix..' '..field..' # '..#thisValue..'\n')
				resizeArrayWithValue(lastValue, #thisValue, nil)
			end

			--do return end
			-- this code is whats running at half the speed:
			-- in the inline code it just calls encodeSpell()
			-- but here it's gotta route all the way through the netsend / netreceive

			-- a big chunk of the lost time was this append being in the array ...
			-- 240fps without any of this, 170fps with the concat outside the loop, 140fps with the concat inside...
			local elemPrefix = prefix..' '..field

			for index,thisElem in ipairs(thisValue) do	-- for = is 165fps, for in is 150fps
				-- the non-inline has to send the value separately
				-- while the inline doesn't
				-- maybe if __netsend sent the value across as well?  one less dereference...
				netField:__netsend(socket, elemPrefix, index, thisValue, lastValue, thisElem)
			end
		end,
	}
end

return {
	netescape = netescape,
	netunescape = netunescape,
	NetField = NetField,
	NetFieldObject = NetFieldObject,
	netSendObj = netSendObj,
	netReceiveObj = netReceiveObj,
	netFieldBoolean = netFieldBoolean,
	netFieldNumber = netFieldNumber,
	netFieldNumberOrNil = netFieldNumberOrNil,
	netFieldString = netFieldString,
	netFieldStringOrNil = netFieldStringOrNil,
	netFieldList = netFieldList,
}
