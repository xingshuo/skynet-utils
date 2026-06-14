local Skynet = require "skynet"
local Const = require "timer.const"

local TIMER_TAG_REPEAT = assert(Const.TIMER_TAG_REPEAT)

local TIMER_KEY_NEXT_TS = assert(Const.TIMER_KEY_NEXT_TS)
local TIMER_KEY_SEQ = assert(Const.TIMER_KEY_SEQ)
local TIMER_KEY_INTERVAL = assert(Const.TIMER_KEY_INTERVAL)
local TIMER_KEY_FUNC = assert(Const.TIMER_KEY_FUNC)

-- 基于全量遍历管理用户定时器
---@class CSimpleImpl
local CSimpleImpl = DefClass("timer.CSimpleImpl")

function CSimpleImpl:_Ctor()
	self.__timers = {}
end

function CSimpleImpl:Push(timer)
	local seq = timer[TIMER_KEY_SEQ]
	self.__timers[seq] = timer
end

function CSimpleImpl:OnTick(manager, now)
	for seq, timer in pairs(self.__timers) do
		local func = timer[TIMER_KEY_FUNC]
		if not func then -- removed
			manager.__timers[seq] = nil
			self.__timers[seq] = nil
		elseif timer[TIMER_KEY_NEXT_TS] <= now then
			if (seq & TIMER_TAG_REPEAT) == TIMER_TAG_REPEAT then
				timer[TIMER_KEY_NEXT_TS] = now + timer[TIMER_KEY_INTERVAL]
			else
				manager.__timers[seq] = nil
				self.__timers[seq] = nil
			end
			-- should not block
			Skynet.fork(func)
		end
	end
end

local M = {}

M.CSimpleImpl = CSimpleImpl

return M