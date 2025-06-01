local table = require 'ext.table'
local ast = require 'parser.lua.ast'
local NetField = require 'netrefl.netfield'.NetField
local vec2 = require 'vec.vec2'
local vec3 = require 'vec.vec3'
local vec4 = require 'vec.vec4'

-- ast.exec env, for vec table access
local env = setmetatable({}, {__index=_G})
env.vec2 = vec2
env.vec3 = vec3
env.vec4 = vec4

local resultClasses = {}

-- net encode/decode
for dim=2,4 do
	local classname = 'vec'..dim
	local netclassname = 'netFieldVec'..dim
	local nc = NetField:subclass()
	resultClasses[netclassname] = nc
	env[netclassname] = nc

	do
		local exprs = table()
		for i=1,dim do
			if i > 1 then
				exprs:insert(ast._string(' '))
			end
			exprs:insert(ast._index(ast._arg(1), ast._number(i)))
		end
		nc.func__netencode = ast._function(
			ast._index(ast._var(netclassname), ast._string'__netencode'),
			{ast._arg()},
			ast._return(
				ast._concat(exprs:unpack())
		))
--DEBUG:print(classname, '__netencode', nc.func__netencode:toLua())
		assert(nc.func__netencode:exec(nil, nil, env))()
	end

	do
		local exprs = table()
		for i=1,dim do
			exprs:insert(ast._call(
				ast._indexself(ast._var'arg1', 'next')
			))
		end
		nc.func__netparse = ast._function(
			ast._index(ast._var(netclassname), ast._string'__netparse'),
			{ast._arg()},
			ast._return(
				ast._call(ast._var(classname),
					exprs:unpack()
		)))
--DEBUG:print(classname, '__netparse', nc.func__netparse:toLua())
		assert(nc.func__netparse:exec(nil, nil, env))()
	end

	do
		local stmts = {}
		table.insert(stmts, ast._if(
			ast._not(ast._arg(2)),
			ast._assign({ast._arg(2)}, {ast._call(ast._var(classname))})
		))
		for i=1,dim do
			table.insert(stmts,
				ast._assign(
					{ast._index(ast._arg(2), ast._number(i))},
					{ast._index(ast._arg(1), ast._number(i))}
			))
		end
		table.insert(stmts, ast._return(ast._arg(2)))
		nc.func__netcopy = ast._function(
			ast._index(ast._var(netclassname), ast._string'__netcopy'),
			{ast._arg(),ast._arg()},	-- src, body
			table.unpack(stmts)
		)
--DEBUG:print(classname, '__netcopy', nc.func__netcopy:toLua())
		assert(nc.func__netcopy:exec(nil, nil, env))()
	end

	-- should be the same as not a == b ?
	nc.__netdiff = function(a,b) return a ~= b end
	--nc.__netsend = NetField.__netsend	-- inherit from parent
end

return resultClasses
