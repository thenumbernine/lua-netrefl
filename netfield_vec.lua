local class = require 'ext.class'
require 'vec'
require 'parser.ast'
require 'netrefl.netfield'

-- net encode/decode
for dim=2,4 do
	local classname = 'vec'..dim
	local netclassname = 'netFieldVec'..dim
	local nc = class(NetField)
	_G[netclassname] = nc

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
		ast.exec(nc.func__netencode)()
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
		ast.exec(nc.func__netparse)()
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
		ast.exec(nc.func__netcopy)()
	end
	
	-- should be the same as not a == b ?
	nc.__netdiff = function(a,b) return a ~= b end
	--nc.__netsend = NetField.__netsend	-- inherit from parent
end

