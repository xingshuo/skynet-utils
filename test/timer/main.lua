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

-- 系统定时器由 skynet.timeout 驱动，不依赖 OnTick，因此单独测试
local function newSysTimersAndRun(mode, ...)
	Log.InfoF("-----------------SYS_TIMER(%s) TEST BEGIN------------------", getMapKey(TIMER_IMPL, mode))
	local manager = Timer.CTimerManager:New(mode, ...)
	local now = Date.CentiSecond()

	-- 单次系统定时器
	local s1
	s1 = manager:NewSysTimer(function()
		Log.InfoF("run sys once timer seq[%d] timeout at %d diff", s1, Date.CentiSecond() - now)
	end, 50, false)
	Log.InfoF("new sys once timer seq[%d] interval 50", s1)

	-- 重复系统定时器，触发 count 次后自行停止
	local count = 3
	local i = 0
	local s2
	s2 = manager:NewSysTimer(function()
		i = i + 1
		Log.InfoF("run sys repeat timer seq[%d] timeout at %d diff, %dst", s2, Date.CentiSecond() - now, i)
		if i >= count then
			manager:StopTimer(s2)
			Log.InfoF("sys repeat timer seq[%d] stopped", s2)
		end
	end, 30, true)
	Log.InfoF("new sys repeat timer seq[%d] interval 30, count: %d", s2, count)

	-- 创建后立即停止，验证回调不会触发
	local s3
	s3 = manager:NewSysTimer(function()
		Log.ErrorF("sys cancelled timer seq[%d] should NOT fire!", s3)
	end, 40, false)
	manager:StopTimer(s3)
	Log.InfoF("new sys cancel timer seq[%d] stopped before fire", s3)

	-- 系统定时器由 skynet 驱动，等待其全部触发完成即可，无需 OnTick
	while manager:TimerNum() > 0 do
		Skynet.sleep(10)
	end
	-- 等待已停止定时器残留的 timeout 触发(空转)并清理占位
	Skynet.sleep(50)
	Log.InfoF("-----------------SYS_TIMER(%s) TEST END------------------", getMapKey(TIMER_IMPL, mode))
end

Skynet.start(function()
	newTimersAndRun(10, {{5, 3}, 100, 300, 500, 600, {610, 2}, 700, 770, 800, 1200, 1220}, TIMER_IMPL.HASHED_WHEEL, 10, 60)
	newTimersAndRun(10, {{5, 3}, 100, 300, 500, 600, {610, 2}, 700, 770, 800, 1200, 1220}, TIMER_IMPL.HEAP_QUEUE)
	newTimersAndRun(10, {{5, 3}, 100, 300, 500, 600, {610, 2}, 700, 770, 800, 1200, 1220}, TIMER_IMPL.INTERVAL_QUEUE)
	newTimersAndRun(10, {{5, 3}, 100, 300, 500, 600, {610, 2}, 700, 770, 800, 1200, 1220}, TIMER_IMPL.SIMPLE)
	newTimersAndRun(10, {{5, 3}, 100, 300, 500, 600, {610, 2}, 700, 770, 800, 1200, 1220}, TIMER_IMPL.TIMING_WHEEL, 10, {30, 4})
	-- 系统定时器与 impl 无关，任选一种 mode 构造 manager 即可
	newSysTimersAndRun(TIMER_IMPL.SIMPLE)
	Skynet.exit()
end)