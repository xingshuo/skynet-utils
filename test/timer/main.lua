local Skynet = require "skynet"
local Const = require "timer.const"
local Timer = require "timer.timer"
local Log = require "log"
local Date = require "date"

local TIMER_IMPL = assert(Const.TIMER_IMPL)

local function testHashedWheelTimers(accuracy, size, timeoutList)
	local now = Date.CentiSecond()
	local tm = Timer.CTimerManager:New(TIMER_IMPL.HASHED_WHEEL, accuracy, size)
	for _, timeout in ipairs(timeoutList) do
		local interval, count
		if type(timeout) == 'table' then
			interval = timeout[1]
			count = timeout[2]
		else
			interval = timeout
			count = 1
		end
		local is_repeat = count > 1
		local seq
		local i = 0
		seq = tm:NewTimer(function()
			i = i + 1
			Log.InfoF("timer seq[%d] timeout at %d diff, %dst", seq, Date.CentiSecond() - now, i)
			if is_repeat and i >= count then
				tm:StopTimer(seq)
				Log.InfoF("timer seq[%d] stopped", seq)
			end
		end, interval, is_repeat)
		Log.InfoF("new timer seq[%d] interval %d, count: %d", seq, interval, count)
	end
end

Skynet.start(function()
	testHashedWheelTimers(10, 60, {100, 300, 500, 600, 610, 700, 770, 800})
	print("timer run start!")
	while tm:TimerNum() > 0 do
		Skynet.sleep(10)
		tm:OnTick()
	end
	print("timer run end!")
	Skynet.exit()
end)