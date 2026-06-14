local Skynet = require "skynet"
local Const = require "timer.const"
local Heapq = require "container.heapq"

local TIMER_TAG_REPEAT = assert(Const.TIMER_TAG_REPEAT)

local TIMER_KEY_NEXT_TS = assert(Const.TIMER_KEY_NEXT_TS)
local TIMER_KEY_SEQ = assert(Const.TIMER_KEY_SEQ)
local TIMER_KEY_INTERVAL = assert(Const.TIMER_KEY_INTERVAL)
local TIMER_KEY_FUNC = assert(Const.TIMER_KEY_FUNC)

local function _timerLeCmp(t1, t2)
	return t1[TIMER_KEY_NEXT_TS] <= t2[TIMER_KEY_NEXT_TS]
end

-- 基于优先队列管理用户定时器
---@class CHeapqImpl
local CHeapqImpl = DefClass("timer.CHeapqImpl")

function CHeapqImpl:_Ctor()
	self.__heap = {
		__le_cmp = _timerLeCmp,
	}
end

function CHeapqImpl:Push(timer)
	Heapq.Push(self.__heap, timer)
end

function CHeapqImpl:OnTick(manager, now)
	while #self.__heap > 0 do
		local timer = self.__heap[1]
		local seq = timer[TIMER_KEY_SEQ]
		local func = timer[TIMER_KEY_FUNC]
		if not func then -- removed
			manager.__timers[seq] = nil
			Heapq.Pop(self.__heap)
		elseif timer[TIMER_KEY_NEXT_TS] > now then
			break
		else
			if (seq & TIMER_TAG_REPEAT) == TIMER_TAG_REPEAT then
				timer[TIMER_KEY_NEXT_TS] = now + timer[TIMER_KEY_INTERVAL]
				Heapq.Replace(self.__heap, timer)
			else
				manager.__timers[seq] = nil
				Heapq.Pop(self.__heap)
			end
			-- should not block
			Skynet.fork(func)
		end
	end
end

local M = {}

M.CHeapqImpl = CHeapqImpl

return M