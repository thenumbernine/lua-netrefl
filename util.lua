
-- coroutine function that blocks til it gets something
function receiveBlocking(conn, waitduration, secondsTimerFunc)
	coroutine.yield()
	
	if not secondsTimerFunc then
		secondsTimerFunc = os.time	-- better provide your own ...
	end

	local endtime
	if waitduration then 
		endtime = secondsTimerFunc() + waitduration
	end
	local data
	repeat
		coroutine.yield()
		local reason
		data, reason = conn:receive('*l')
		if not data then
			if reason ~= 'timeout' then
				return nil, reason		-- error() ?
			end
			-- else continue
			if waitduration and secondsTimerFunc() > endtime then
				return nil, 'timeout'
			end
		end
	until data ~= nil

	return data
end
