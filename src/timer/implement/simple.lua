local Skynet = require "skynet"
local Const = require "timer.const"

local TIMER_TAG_REPEAT = assert(Const.TIMER_TAG_REPEAT)

local TIMER_KEY_NEXT_TS = assert(Const.TIMER_KEY_NEXT_TS)
local TIMER_KEY_SEQ = assert(Const.TIMER_KEY_SEQ)
local TIMER_KEY_INTERVAL = assert(Const.TIMER_KEY_INTERVAL)
local TIMER_KEY_FUNC = assert(Const.TIMER_KEY_FUNC)

local MAX_TS = math.maxinteger

-- 基于全量遍历管理用户定时器
---@class CSimpleImpl
local CSimpleImpl = DefClass("timer.CSimpleImpl")

function CSimpleImpl:_Ctor()
	self.__timers = {}
	self.__min_ts = MAX_TS
end

function CSimpleImpl:Push(timer)
	local seq = timer[TIMER_KEY_SEQ]
	self.__timers[seq] = timer
	local next_ts = timer[TIMER_KEY_NEXT_TS]
	if next_ts < self.__min_ts then
		self.__min_ts = next_ts
	end
end

function CSimpleImpl:OnRemove(timer)
	local seq = timer[TIMER_KEY_SEQ]
	self.__timers[seq] = nil
end

function CSimpleImpl:OnTick(manager, now)
	local min_ts = self.__min_ts
	if min_ts > now then
		return
	end

	min_ts = MAX_TS
	for seq, timer in pairs(self.__timers) do
		local func = timer[TIMER_KEY_FUNC]
		if not func then -- removed
			manager.__timers[seq] = nil
			self.__timers[seq] = nil
		elseif timer[TIMER_KEY_NEXT_TS] <= now then
			if (seq & TIMER_TAG_REPEAT) == TIMER_TAG_REPEAT then
				local next_ts = now + timer[TIMER_KEY_INTERVAL]
				timer[TIMER_KEY_NEXT_TS] = next_ts
				if next_ts < min_ts then
					min_ts = next_ts
				end
			else
				manager.__timers[seq] = nil
				self.__timers[seq] = nil
			end
			-- should not block
			Skynet.fork(func)
		else
			if timer[TIMER_KEY_NEXT_TS] < min_ts then
				min_ts = timer[TIMER_KEY_NEXT_TS]
			end
		end
	end
	self.__min_ts = min_ts
end

local M = {}

M.CSimpleImpl = CSimpleImpl

return M