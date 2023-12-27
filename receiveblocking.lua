-- coroutine function that blocks til it gets something
local function receiveBlocking(conn, waitduration, secondsTimerFunc)
	coroutine.yield()
	
	if not secondsTimerFunc then
		secondsTimerFunc = require 'ext.timer'.getTime
	end

	local endtime
	if waitduration then 
		endtime = secondsTimerFunc() + waitduration
	end
	local data
	repeat
		coroutine.yield()
		local reason
		data, reason = conn:receive'*l'
----DEBUG:print(secondsTimerFunc(), 'conn:receive', data, reason)	
		if not data then
			if reason == 'wantread' then
----DEBUG:print(secondsTimerFunc(), 'got wantread, calling select...')
				socket.select(nil, {conn})
----DEBUG:print(secondsTimerFunc(), '...done calling select')
			else
				if reason ~= 'timeout' then
					return nil, reason		-- error() ?
				end
				-- else continue
				if waitduration and secondsTimerFunc() > endtime then
----DEBUG:print(secondsTimerFunc(), '...exceeded wait duration of '..waitduration..', returning "timeout"')
					return nil, 'timeout'
				end
			end
		end
	until data ~= nil

--DEBUG:print("receiveBlocking returning", data)
	return data
end

return receiveBlocking
