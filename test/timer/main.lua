local Skynet = require "skynet"
local Const = require "timer.const"
local Timer = require "timer.timer"
local Log = require "log"
local Date = require "date"

local TIMER_IMPL = assert(Const.TIMER_IMPL)

local function getMapKey(map, value)
	for k, v in pairs(map) do
		if v == value then
			return k
		end
	end
end

local function newTimersAndRun(tickPeriod, timeoutList, mode, ...)
	Log.InfoF("-----------------%s TEST BEGIN------------------", getMapKey(TIMER_IMPL, mode))
	local manager = Timer.CTimerManager:New(mode, ...)
	local now = Date.CentiSecond()
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
		seq = manager:NewTimer(function()
			i = i + 1
			Log.InfoF("run timer seq[%d] timeout at %d diff, %dst", seq, Date.CentiSecond() - now, i)
			if is_repeat and i >= count then
				manager:StopTimer(seq)
				Log.InfoF("timer seq[%d] stopped", seq)
			end
		end, interval, is_repeat)
		Log.InfoF("new timer seq[%d] interval %d, count: %d", seq, interval, count)
	end

	Log.InfoF("tick timers start!")
	while manager:TimerNum() > 0 do
		Skynet.sleep(tickPeriod)
		manager:OnTick()
	end
	-- let all fork run
	Skynet.sleep(1)
	Log.InfoF("tick timers end!")
	Log.InfoF("-----------------%s TEST END------------------", getMapKey(TIMER_IMPL, mode))
end

Skynet.start(function()
	newTimersAndRun(10, {100, 300, 500, 600, {610, 2}, 700, 770, 800, 1200, 1220}, TIMER_IMPL.HASHED_WHEEL, 10, 60)
	newTimersAndRun(10, {100, 300, 500, 600, {610, 2}, 700, 770, 800, 1200, 1220}, TIMER_IMPL.HEAP_QUEUE)
	newTimersAndRun(10, {100, 300, 500, 600, {610, 2}, 700, 770, 800, 1200, 1220}, TIMER_IMPL.SEQUENCE)
	newTimersAndRun(10, {100, 300, 500, 600, {610, 2}, 700, 770, 800, 1200, 1220}, TIMER_IMPL.SIMPLE)
	newTimersAndRun(10, {100, 300, 500, 600, {610, 2}, 700, 770, 800, 1200, 1220}, TIMER_IMPL.TIMING_WHEEL, 10, {30, 4})
	Skynet.exit()
end)