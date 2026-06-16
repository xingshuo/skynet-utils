local Skynet = require "skynet"
local Const = require "timer.const"
local HashedWheel = require "timer.implement.hashed_wheel"
local HeapQueue = require "timer.implement.heap_queue"
local Sequence = require "timer.implement.sequence"
local Simple = require "timer.implement.simple"
local TimingWheel = require "timer.implement.timing_wheel"
local Log = require "log"
local Date = require "date"

local hpc = Skynet.hpc -- 单调纳秒计数器，用于高精度计时

-- timer 表字段下标（与 Const 对齐，直接构造避免走 manager 的 seq 分配开销）
local K_NEXT_TS = assert(Const.TIMER_KEY_NEXT_TS)
local K_SEQ = assert(Const.TIMER_KEY_SEQ)
local K_INTERVAL = assert(Const.TIMER_KEY_INTERVAL)
local K_FUNC = assert(Const.TIMER_KEY_FUNC)
local TAG_USER = assert(Const.TIMER_TAG_USER)
local TAG_REPEAT = assert(Const.TIMER_TAG_REPEAT)
local SHIFT = assert(Const.TIMER_TYPE_SHIFT)

--==========================================================================--
-- 可调参数
--==========================================================================--
local ACCURACY = 1                  -- 时间轮精度（厘秒）；取 1 让 1 tick = 1 时间单位，便于对齐
local HASH_SIZE = 1024              -- 单层时间轮槽数
local TW_LEVELS = {256, 64, 64}     -- 多层时间轮各层槽数，覆盖 256*64*64 ≈ 1.05M tick
-- drain 的到期窗口固定（不随 N 变化）：让“密度”随 N 增长而“时间跨度”恒定，
-- 否则单层时间轮的 rounds 记账会随跨度线性膨胀，drain 退化为近似 O(N*跨度/size)。
local DRAIN_WINDOW = 65536          -- < TW 覆盖范围，> HASH_SIZE（rounds 上限 ≈ 64）

-- 各 benchmark 的数据量级（如需更大量级直接改这里）
local DRAIN_NS = {1000, 10000, 100000, 1000000}
local IDLE_NS = {1000, 10000, 100000}
local IDLE_TICKS = 1000             -- idle benchmark 空转的 tick 次数
local SEED = 20240601

-- 游戏场景 benchmark：大量短期重复 timer + 少量长期 timer，稳态运行一段时间
local REPEAT_NS = {1000, 10000, 100000}
local SIM_CENTISEC = 6000           -- 模拟运行时长（厘秒）= 60s
local TICK_PERIOD = 10              -- OnTick 调用周期（厘秒）= 100ms，模拟服务器 tick
local LONG_RATIO = 0.05             -- 长期定时器占比（少量）
local SHORT_INTERVALS = {300, 500, 1000, 1200, 1500, 2000, 3000}    -- 3/5/10/12/15/20/30 s
local LONG_INTERVALS = {6000, 30000, 60000, 360000}                 -- 1/5/10/60 min

--==========================================================================--
-- 工具
--==========================================================================--
local NOOP = function() end

-- fork 桩：隔离 coroutine 开销，仅计数，便于校验“是否全部触发”
-- 注意：真实 OnTick 会对每个到期 timer 多做一次 Skynet.fork(协程调度)，
--       该开销 5 种实现一致，不影响相对比较，但绝对值不含在本基准内。
local fireCount = 0
local realFork = Skynet.fork
local function installForkStub()
	Skynet.fork = function() fireCount = fireCount + 1 end
end
local function restoreFork()
	Skynet.fork = realFork
end

-- 假 manager，仅提供 __timers 供 impl 回写
local function newFakeManager()
	return { __timers = {} }
end

local function makeImpls()
	return {
		{ name = "SIMPLE", new = function() return Simple.CSimpleImpl:New() end },
		{ name = "HEAP_QUEUE", new = function() return HeapQueue.CHeapqImpl:New() end },
		{ name = "SEQUENCE", new = function() return Sequence.CSequenceImpl:New() end },
		{ name = "HASHED_WHEEL", new = function() return HashedWheel.CHashedWheelImpl:New(ACCURACY, HASH_SIZE) end },
		{ name = "TIMING_WHEEL", new = function() return TimingWheel.CTimingWheelImpl:New(ACCURACY, TW_LEVELS) end },
	}
end

-- 预构造 n 个 timer 表；intervalFn(i) 返回该 timer 的 interval
local function buildTimers(n, base, intervalFn)
	local timers = {}
	for i = 1, n do
		local interval = intervalFn(i)
		local seq = (i << SHIFT) | TAG_USER -- 一次性用户 timer，seq 唯一
		timers[i] = { [K_NEXT_TS] = base + interval, [K_SEQ] = seq, [K_INTERVAL] = interval, [K_FUNC] = NOOP }
	end
	return timers
end

local function pad(s, w)
	s = tostring(s)
	if #s >= w then return s end
	return s .. string.rep(" ", w - #s)
end

--==========================================================================--
-- Benchmark 1: Push + Drain（随机散布的到期时间）
-- 衡量插入吞吐、内存占用，以及一次性触发全部 timer 的耗时
--==========================================================================--
local function benchDrain(n)
	Log.InfoF("===== PUSH + DRAIN  N=%d  (随机 interval ∈ [1,%d]) =====", n, DRAIN_WINDOW)
	Log.InfoF("%s%s%s%s",
		pad("impl", 16), pad("push(ms)", 14), pad("mem(KB)", 14), pad("drain(ms)", 14))

	-- 同一份 interval 数据复用到 5 种实现，保证公平
	math.randomseed(SEED)
	local W = DRAIN_WINDOW
	local intervals = {}
	for i = 1, n do intervals[i] = math.random(1, W) end

	for _, impl in ipairs(makeImpls()) do
		local base = Date.CentiSecond()
		local timers = buildTimers(n, base, function(i) return intervals[i] end)

		collectgarbage("collect")
		local memBefore = collectgarbage("count")
		collectgarbage("stop")

		local mgr = newFakeManager()
		local inst = impl.new()

		-- Push
		local t0 = hpc()
		for i = 1, n do
			inst:Push(timers[i])
		end
		local pushMs = (hpc() - t0) / 1e6

		collectgarbage("restart")
		collectgarbage("collect")
		local memKB = collectgarbage("count") - memBefore
		collectgarbage("stop")

		-- Drain：把 now 推进到超过最大 interval，一次 OnTick 触发全部
		fireCount = 0
		local nowEnd = base + W + ACCURACY
		t0 = hpc()
		inst:OnTick(mgr, nowEnd)
		local drainMs = (hpc() - t0) / 1e6

		collectgarbage("restart")

		local mark = (fireCount == n) and "" or string.format("  <FIRES=%d!=%d>", fireCount, n)
		Log.InfoF("%s%s%s%s%s",
			pad(impl.name, 16),
			pad(string.format("%.3f", pushMs), 14),
			pad(string.format("%.1f", memKB), 14),
			pad(string.format("%.3f", drainMs), 14),
			mark)

		timers = nil
		inst = nil
		mgr = nil
		collectgarbage("collect")
	end
end

--==========================================================================--
-- Benchmark 2: Idle OnTick（无任何 timer 到期，纯空转开销）
-- 用“互不相同的远期 interval”，暴露各结构每 tick 的固定遍历成本：
--   SIMPLE     ~ O(N)/tick
--   SEQUENCE   ~ O(#groups)/tick （此处 N 个不同 interval => N 个组）
--   HASHED_WHEEL ~ O(N/size)/tick （rounds 记账）
--   HEAP_QUEUE ~ O(1)/tick
--   TIMING_WHEEL ~ O(levels)/tick（含周期性进位）
--==========================================================================--
local function benchIdle(n)
	Log.InfoF("===== IDLE TICK  N=%d  T=%d  (互异远期 interval，全程不触发) =====", n, IDLE_TICKS)
	Log.InfoF("%s%s%s%s",
		pad("impl", 16), pad("push(ms)", 14), pad("mem(KB)", 14), pad("idle(us/tick)", 16))

	local idleBase = IDLE_TICKS * ACCURACY + 100 -- 保证所有 timer 在 T tick 内都不到期

	for _, impl in ipairs(makeImpls()) do
		local base = Date.CentiSecond()
		local timers = buildTimers(n, base, function(i) return idleBase + i end)

		collectgarbage("collect")
		local memBefore = collectgarbage("count")
		collectgarbage("stop")

		local mgr = newFakeManager()
		local inst = impl.new()

		local t0 = hpc()
		for i = 1, n do
			inst:Push(timers[i])
		end
		local pushMs = (hpc() - t0) / 1e6

		collectgarbage("restart")
		collectgarbage("collect")
		local memKB = collectgarbage("count") - memBefore
		collectgarbage("stop")

		-- 空转 T 次，每次推进 1 个 tick；不应触发任何 timer
		fireCount = 0
		local startNow = base
		t0 = hpc()
		for k = 1, IDLE_TICKS do
			inst:OnTick(mgr, startNow + k * ACCURACY)
		end
		local totalNs = hpc() - t0
		local usPerTick = totalNs / 1e3 / IDLE_TICKS

		collectgarbage("restart")

		local mark = (fireCount == 0) and "" or string.format("  <FIRED=%d!>", fireCount)
		Log.InfoF("%s%s%s%s%s",
			pad(impl.name, 16),
			pad(string.format("%.3f", pushMs), 14),
			pad(string.format("%.1f", memKB), 14),
			pad(string.format("%.3f", usPerTick), 16),
			mark)

		timers = nil
		inst = nil
		mgr = nil
		collectgarbage("collect")
	end
end

--==========================================================================--
-- Benchmark 3: 游戏稳态（大量短期 repeat + 少量长期 timer）
-- 全部为 repeat timer，模拟服务器以 TICK_PERIOD 周期 tick SIM_CENTISEC 时长，
-- 衡量“持续重挂载”下的吞吐与每次 OnTick 开销：
--   HEAP_QUEUE   每次触发 O(log n) Replace
--   TIMING_WHEEL 每次重挂载分配一个包装 node（GC 压力）
--   SEQUENCE     仅 ~11 个不同 interval => 极少分组，是其最佳场景
--   HASHED_WHEEL 长期 timer 每圈都要做 rounds 记账
--   SIMPLE       每次 OnTick 恒为 O(N)
-- 初始相位随机打散，避免同周期 timer 在同一 tick 齐射。
--==========================================================================--
local function buildRepeatTimers(n, base)
	local timers = {}
	for i = 1, n do
		local interval
		if math.random() < LONG_RATIO then
			interval = LONG_INTERVALS[math.random(#LONG_INTERVALS)]
		else
			interval = SHORT_INTERVALS[math.random(#SHORT_INTERVALS)]
		end
		local seq = (i << SHIFT) | TAG_USER | TAG_REPEAT
		local firstDelay = math.random(1, interval) -- 随机初始相位
		timers[i] = { [K_NEXT_TS] = base + firstDelay, [K_SEQ] = seq, [K_INTERVAL] = interval, [K_FUNC] = NOOP }
	end
	return timers
end

local function benchRepeat(n)
	Log.InfoF("===== GAME REPEAT  N=%d  sim=%.0fs tick=%dms long=%.0f%% =====",
		n, SIM_CENTISEC / 100, TICK_PERIOD * 10, LONG_RATIO * 100)
	Log.InfoF("%s%s%s%s%s%s",
		pad("impl", 16), pad("push(ms)", 12), pad("mem(KB)", 12),
		pad("sim(ms)", 12), pad("fires", 12), pad("us/call", 12))

	local calls = SIM_CENTISEC // TICK_PERIOD

	for _, impl in ipairs(makeImpls()) do
		math.randomseed(SEED) -- 每种实现用完全相同的 timer 群体，保证公平
		local base = Date.CentiSecond()
		local timers = buildRepeatTimers(n, base)

		collectgarbage("collect")
		local memBefore = collectgarbage("count")
		collectgarbage("stop")

		local mgr = newFakeManager()
		local inst = impl.new()

		local t0 = hpc()
		for i = 1, n do
			inst:Push(timers[i])
		end
		local pushMs = (hpc() - t0) / 1e6

		collectgarbage("restart")
		collectgarbage("collect")
		local memKB = collectgarbage("count") - memBefore

		-- 稳态运行：每 TICK_PERIOD 调一次 OnTick，repeat timer 持续重挂载。
		-- 此处保持 GC 开启：长时间运行下 TIMING_WHEEL 每次重挂载产生的 node 垃圾
		-- 需被回收，让计时包含真实 GC 成本，更贴近线上稳态（也避免 OOM）。
		fireCount = 0
		t0 = hpc()
		for k = 1, calls do
			inst:OnTick(mgr, base + k * TICK_PERIOD)
		end
		local simMs = (hpc() - t0) / 1e6
		local usPerCall = simMs * 1e3 / calls

		Log.InfoF("%s%s%s%s%s%s",
			pad(impl.name, 16),
			pad(string.format("%.3f", pushMs), 12),
			pad(string.format("%.1f", memKB), 12),
			pad(string.format("%.3f", simMs), 12),
			pad(fireCount, 12),
			pad(string.format("%.3f", usPerCall), 12))

		timers = nil
		inst = nil
		mgr = nil
		collectgarbage("collect")
	end
end

Skynet.start(function()
	Log.InfoF("################ TIMER IMPL BENCHMARK BEGIN ################")
	Log.InfoF("ACCURACY=%d HASH_SIZE=%d TW_LEVELS={%s}",
		ACCURACY, HASH_SIZE, table.concat(TW_LEVELS, ","))
	installForkStub()

	for _, n in ipairs(DRAIN_NS) do
		benchDrain(n)
	end
	for _, n in ipairs(IDLE_NS) do
		benchIdle(n)
	end
	for _, n in ipairs(REPEAT_NS) do
		benchRepeat(n)
	end

	restoreFork()
	Log.InfoF("################ TIMER IMPL BENCHMARK END ################")
	Skynet.exit()
end)
