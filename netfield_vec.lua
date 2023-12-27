local ast = require 'parser.ast'
local NetField = require 'netrefl.netfield'.NetField

local vec2 = require 'vec.vec2'
local vec3 = require 'vec.vec3'
local vec4 = require 'vec.vec4'

-- ast.exec env, for vec table access
local env = setmetatable({}, {__index=_G})
env.vecClasses = {
	[2] = vec2, 
	[3] = vec3, 
	[4] = vec4,
}

local resultClasses = {}

-- net encode/decode
for dim=2,4 do
	local classname = 'vec'..dim
	local netclassname = 'netFieldVec'..dim
	local nc = NetField:subclass()
	resultClasses[netclassname] = nc
	env[netclassname] = nc

	do
		local exprs = {}
		for i=1,dim do
			if i > 1 then
				table.insert(exprs, ast._string(' '))
			end
			table.insert(exprs, ast._index(ast._arg(1), i))
		end
		nc.func__netencode = ast._function(
			netclassname..'.__netencode',
			{ast._arg()},
			ast._return(
				ast._concat(unpack(exprs))
		))
		ast.exec(nc.func__netencode, nil, nil, env)()
	end

	do
		local exprs = {}
		for i=1,dim do
			table.insert(exprs, ast._call('arg1:next'))
		end
		nc.func__netparse = ast._function(
			netclassname..'.__netparse',
			{ast._arg()},
			ast._return(
				ast._call(classname,
					unpack(exprs)
		)))
		ast.exec(nc.func__netparse, nil, nil, env)()
	end

	do
		local stmts = {}
		table.insert(stmts, ast._if(
			ast._not(ast._arg(2)),
			ast._assign({ast._arg(2)}, {ast._call(classname)})
		))
		for i=1,dim do
			table.insert(stmts, 
				ast._assign(
					{ast._index(ast._arg(2),i)},
					{ast._index(ast._arg(1),i)}
			))
		end
		table.insert(stmts, ast._return(ast._arg(2)))
		nc.func__netcopy = ast._function(
			netclassname..'.__netcopy',
			{ast._arg(),ast._arg()},	-- src, body
			unpack(stmts)
		)
		ast.exec(nc.func__netcopy, nil, nil, env)()
	end
	
	-- should be the same as not a == b ?
	nc.__netdiff = function(a,b) return a ~= b end
	--nc.__netsend = NetField.__netsend	-- inherit from parent
end

return resultClasses
