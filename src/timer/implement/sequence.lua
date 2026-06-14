local Skynet = require "skynet"
local Const = require "timer.const"

local TIMER_TAG_REPEAT = assert(Const.TIMER_TAG_REPEAT)

local TIMER_KEY_NEXT_TS = assert(Const.TIMER_KEY_NEXT_TS)
local TIMER_KEY_SEQ = assert(Const.TIMER_KEY_SEQ)
local TIMER_KEY_INTERVAL = assert(Const.TIMER_KEY_INTERVAL)
local TIMER_KEY_FUNC = assert(Const.TIMER_KEY_FUNC)

---@class CSequenceImpl
CSequenceImpl = DefClass("timer.CSequenceImpl")

function CSequenceImpl:_Ctor()
	self.__timer_lists = {} -- interval : timer list
end

function CSequenceImpl:Push(timer)
	local interval = timer[TIMER_KEY_INTERVAL]
	local list = self.__timer_lists[interval]
	if not list then
		self.__timer_lists[interval] = {timer, h = 1, t = 1}
	else
		local t = list.t + 1
		list.t = t
		list[t] = timer
	end
end

function CSequenceImpl:OnTick(manager, now)
	for interval, list in pairs(self.__timer_lists) do
		while true do
			if list.h == list.t + 1 then -- queue empty
				list.h = 1
				list.t = 0
				break
			end
			local h = list.h
			local timer = list[h]
			local seq = timer[TIMER_KEY_SEQ]
			local func = timer[TIMER_KEY_FUNC]
			if not func then -- removed
				manager.__timers[seq] = nil
				list[h] = nil
				list.h = h + 1
				goto continue
			end
			if timer[TIMER_KEY_NEXT_TS] > now then
				break
			end
			list[h] = nil
			list.h = h + 1
			if (seq & TIMER_TAG_REPEAT) == TIMER_TAG_REPEAT then
				timer[TIMER_KEY_NEXT_TS] = now + interval
				local t = list.t + 1
				list.t = t
				list[t] = timer
			else
				manager.__timers[seq] = nil
			end
			-- should not block
			Skynet.fork(func)
			::continue::
		end
	end
end