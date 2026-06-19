local Skynet = require "skynet"
local Const = require "timer.const"
local Date = require "date"

local TIMER_TAG_REPEAT = assert(Const.TIMER_TAG_REPEAT)

local TIMER_KEY_NEXT_TS = assert(Const.TIMER_KEY_NEXT_TS)
local TIMER_KEY_SEQ = assert(Const.TIMER_KEY_SEQ)
local TIMER_KEY_INTERVAL = assert(Const.TIMER_KEY_INTERVAL)
local TIMER_KEY_FUNC = assert(Const.TIMER_KEY_FUNC)

-- 基于单层时间轮管理用户定时器
---@class CHashedWheelImpl
local CHashedWheelImpl = DefClass("timer.CHashedWheelImpl")

function CHashedWheelImpl:_Ctor(accuracy, size)
	assert(accuracy >= 1 and accuracy <= 100, accuracy)
	assert(size > 0)
	self.__accuracy = accuracy
	self.__size = size -- bucket size
	self.__buckets = {}
	for i = 1, size do
		self.__buckets[i] = {t = 0} -- FIFO 桶：drain 时整体前移并复位，无需常驻 head 字段
	end
	self.__tick = Date.CentiSecond() // accuracy
	self.__pendings = {n = 0}
end

function CHashedWheelImpl:Push(timer)
	-- 向上取整：在 next_ts 之后的第一个 tick 边界触发，保证“绝不提前”
	local deadlineTick = (timer[TIMER_KEY_NEXT_TS] + self.__accuracy - 1) // self.__accuracy
	if deadlineTick <= self.__tick then
		deadlineTick = self.__tick + 1  -- 至少下一 tick 触发，避免绕满一圈
	end
	timer.rounds = (deadlineTick - self.__tick - 1) // self.__size
	local index = (deadlineTick - 1) % self.__size + 1
	local bucket = self.__buckets[index]
	local t = bucket.t + 1
	bucket.t = t
	bucket[t] = timer
end

function CHashedWheelImpl:OnRemove(timer)
end

function CHashedWheelImpl:OnTick(manager, now)
	local size = self.__size
	local buckets = self.__buckets
	local pendings = self.__pendings
	local tick = self.__tick
	local ticks = (now - tick * self.__accuracy) // self.__accuracy
	for _ = 1, ticks do
		local bucket = buckets[tick % size + 1]
		local tail = bucket.t -- 快照桶长；幸存者前移到 [1..t]，fork 延迟执行，期间不会有新 Push
		local t = 0
		for h = 1, tail do
			local timer = bucket[h]
			bucket[h] = nil
			local seq = timer[TIMER_KEY_SEQ]
			local func = timer[TIMER_KEY_FUNC]
			if not func then -- removed
				manager.__timers[seq] = nil
			elseif timer.rounds > 0 then
				timer.rounds = timer.rounds - 1
				t = t + 1
				bucket[t] = timer
			else
				if (seq & TIMER_TAG_REPEAT) == TIMER_TAG_REPEAT then
					local pn = pendings.n + 1
					pendings.n = pn
					pendings[pn] = timer
				else
					manager.__timers[seq] = nil
				end
				-- should not block
				Skynet.fork(func)
			end
		end
		bucket.t = t
		tick = tick + 1
	end
	self.__tick = tick

	-- 重挂载：锚定到当前轮子刻度(tick*accuracy)而非陈旧 next_ts 或偏晚的 now。
	-- 配合"单次 OnTick 内每个定时器至多触发一次"，now 大跳时直接重新对齐到当前、
	-- 跳过欠账周期，既不累积漂移也不会逐帧补帧。
	for i = 1, pendings.n do
		local timer = pendings[i]
		timer[TIMER_KEY_NEXT_TS] = tick * self.__accuracy + timer[TIMER_KEY_INTERVAL]
		pendings[i] = nil
		self:Push(timer)
	end
	pendings.n = 0
end

local M = {}

M.CHashedWheelImpl = CHashedWheelImpl

return M