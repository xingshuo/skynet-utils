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
		self.__buckets[i] = {h = 1, t = 0}
	end
	self.__tick = 0
	self.__start_ts = Date.CentiSecond()
	self.__pendings = {n = 0}
end

function CHashedWheelImpl:Push(timer)
	local deadlineTick = (timer[TIMER_KEY_NEXT_TS] - self.__start_ts) // self.__accuracy
	timer.rounds = (deadlineTick - self.__tick) // self.__size
	local index = (deadlineTick % self.__size) + 1
	local bucket = self.__buckets[index]
	local t = bucket.t + 1
	bucket.t = t
	bucket[t] = timer
end

function CHashedWheelImpl:OnTick(manager, now)
	local elapse = now - (self.__start_ts + self.__tick * self.__accuracy)
	local walkTick = elapse // self.__accuracy
	if walkTick <= 0 then
		return
	end

	for i = 1, walkTick do
		local index = (self.__tick + i - 1) % self.__size + 1
		local bucket = self.__buckets[index]
		local t = 0
		while true do
			if bucket.h == bucket.t + 1 then -- traverse to end
				bucket.h = 1
				bucket.t = t
				break
			end
			local h = bucket.h
			local timer = bucket[h]
			bucket[h] = nil
			bucket.h = h + 1
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
					timer[TIMER_KEY_NEXT_TS] = now + timer[TIMER_KEY_INTERVAL]
					local pn = self.__pendings.n + 1
					self.__pendings.n = pn
					self.__pendings[pn] = timer
				else
					manager.__timers[seq] = nil
				end
				-- should not block
				Skynet.fork(func)
			end
		end
	end
	self.__tick = self.__tick + walkTick

	for i = 1, self.__pendings.n do
		local timer = self.__pendings[i]
		self.__pendings[i] = nil
		self:Push(timer)
	end
	self.__pendings.n = 0
end

local M = {}

M.CHashedWheelImpl = CHashedWheelImpl

return M