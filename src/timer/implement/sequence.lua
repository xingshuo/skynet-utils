local Skynet = require "skynet"
local Const = require "timer.const"

local TIMER_TAG_REPEAT = assert(Const.TIMER_TAG_REPEAT)

local TIMER_KEY_NEXT_TS = assert(Const.TIMER_KEY_NEXT_TS)
local TIMER_KEY_SEQ = assert(Const.TIMER_KEY_SEQ)
local TIMER_KEY_INTERVAL = assert(Const.TIMER_KEY_INTERVAL)
local TIMER_KEY_FUNC = assert(Const.TIMER_KEY_FUNC)

-- 基于触发间隔分组队列管理用户定时器
---@class CSequenceImpl
local CSequenceImpl = DefClass("timer.CSequenceImpl")

function CSequenceImpl:_Ctor()
	self.__groups = {} -- interval : timer queue
end

function CSequenceImpl:Push(timer)
	local interval = timer[TIMER_KEY_INTERVAL]
	local queue = self.__groups[interval]
	if not queue then
		self.__groups[interval] = {timer, h = 1, t = 1}
	else
		local t = queue.t + 1
		queue.t = t
		queue[t] = timer
	end
end

function CSequenceImpl:OnTick(manager, now)
	for interval, queue in pairs(self.__groups) do
		while true do
			if queue.h == queue.t + 1 then -- queue empty
				queue.h = 1
				queue.t = 0
				break
			end
			local h = queue.h
			local timer = queue[h]
			local seq = timer[TIMER_KEY_SEQ]
			local func = timer[TIMER_KEY_FUNC]
			if not func then -- removed
				manager.__timers[seq] = nil
				queue[h] = nil
				queue.h = h + 1
			elseif timer[TIMER_KEY_NEXT_TS] > now then
				break
			else
				queue[h] = nil
				queue.h = h + 1
				if (seq & TIMER_TAG_REPEAT) == TIMER_TAG_REPEAT then
					timer[TIMER_KEY_NEXT_TS] = now + interval
					local t = queue.t + 1
					queue.t = t
					queue[t] = timer
				else
					manager.__timers[seq] = nil
				end
				-- should not block
				Skynet.fork(func)
			end
		end
	end
end

local M = {}

M.CSequenceImpl = CSequenceImpl

return M