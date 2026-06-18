local Skynet = require "skynet"
local Const = require "timer.const"
local TimingWheel = require "container.timing_wheel"
local Date = require "date"

local max = math.max

local TIMER_TAG_REPEAT = assert(Const.TIMER_TAG_REPEAT)

local TIMER_KEY_NEXT_TS = assert(Const.TIMER_KEY_NEXT_TS)
local TIMER_KEY_SEQ = assert(Const.TIMER_KEY_SEQ)
local TIMER_KEY_INTERVAL = assert(Const.TIMER_KEY_INTERVAL)
local TIMER_KEY_FUNC = assert(Const.TIMER_KEY_FUNC)

-- 节点在轮中的绝对到期 tick。用字符串键而非整数下标：timer 表本是 {[1..4]} 的纯数组段，
-- 加整数 [5] 会让 Lua 数组段按 pow2 撑到 8（浪费 3 槽）；字符串键只多一个 hash node，更省。
local EXPIRE_KEY = "expire"

-- 基于多层时间轮管理用户定时器
---@class CTimingWheelImpl
local CTimingWheelImpl = DefClass("timer.CTimingWheelImpl")

---@param accuracy number 厘秒
---@param levelList table
function CTimingWheelImpl:_Ctor(accuracy, levelList)
	assert(accuracy >= 1 and accuracy <= 100, accuracy)
	self.__accuracy = accuracy
	self.__tw = TimingWheel.CTimingWheel:New(levelList, EXPIRE_KEY)
	self.__ts = Date.CentiSecond()
	self.__timeouts = {}
	self.__pendings = {n = 0}
end

function CTimingWheelImpl:Push(timer)
	local interval = max(timer[TIMER_KEY_NEXT_TS] - self.__ts, 1)
	local delta = (interval - 1)//self.__accuracy + 1
	self.__tw:Push(timer, delta)
end

function CTimingWheelImpl:OnRemove(timer)
end

function CTimingWheelImpl:OnTick(manager, now)
	local elapse = now - self.__ts
	local tick = elapse // self.__accuracy
	if tick <= 0 then
		return
	end

	for _ = 1, tick do
		local tn = self.__tw:Update(self.__timeouts)
		for i = 1, tn do
			local timer = self.__timeouts[i]
			self.__timeouts[i] = nil
			local seq = timer[TIMER_KEY_SEQ]
			local func = timer[TIMER_KEY_FUNC]
			if not func then -- removed
				manager.__timers[seq] = nil
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
	self.__ts = self.__ts + (tick * self.__accuracy)

	for i = 1, self.__pendings.n do
		local timer = self.__pendings[i]
		self.__pendings[i] = nil
		self:Push(timer)
	end
	self.__pendings.n = 0
end

local M = {}

M.CTimingWheelImpl = CTimingWheelImpl

return M