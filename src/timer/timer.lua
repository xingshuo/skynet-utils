local Skynet = require "skynet"
local Const = require "timer.const"
local HashedWheel = require "timer.implement.hashed_wheel"
local HeapQueue = require "timer.implement.heap_queue"
local Sequence = require "timer.implement.sequence"
local Simple = require "timer.implement.simple"
local TimingWheel = require "timer.implement.timing_wheel"
local ClassFactory = require "infra.class_factory"
local Log = require "log"
local Date = require "date"

local sformat = string.format
local assert = assert

local TIMER_IMPL = assert(Const.TIMER_IMPL)

local TIMER_TAG_USER = assert(Const.TIMER_TAG_USER)
local TIMER_TAG_REPEAT = assert(Const.TIMER_TAG_REPEAT)

local TIMER_KEY_NEXT_TS = assert(Const.TIMER_KEY_NEXT_TS)
local TIMER_KEY_SEQ = assert(Const.TIMER_KEY_SEQ)
local TIMER_KEY_INTERVAL = assert(Const.TIMER_KEY_INTERVAL)
local TIMER_KEY_FUNC = assert(Const.TIMER_KEY_FUNC)

local TIMER_SESSION_MAX = assert(Const.TIMER_SESSION_MAX)
local TIMER_TYPE_SHIFT = assert(Const.TIMER_TYPE_SHIFT)

local ITimerImpl = {}

function ITimerImpl:Push(timer)
end

function ITimerImpl:OnTick(manager, now)
end

---@class CTimerManager
local CTimerManager = DefClass("CTimerManager")

function CTimerManager:_Ctor(mode, ...)
	self.__timers = {}
	self.__session = 0
	if mode == TIMER_IMPL.HASHED_WHEEL then
		self.__impl = HashedWheel.CHashedWheelImpl:New(...)
	elseif mode == TIMER_IMPL.HEAP_QUEUE then
		self.__impl = HeapQueue.CHeapqImpl:New(...)
	elseif mode == TIMER_IMPL.SEQUENCE then
		self.__impl = Sequence.CSequenceImpl:New(...)
	elseif mode == TIMER_IMPL.SIMPLE then
		self.__impl = Simple.CSimpleImpl:New(...)
	elseif mode == TIMER_IMPL.TIMING_WHEEL then
		self.__impl = TimingWheel.CTimingWheelImpl:New(...)
	else
		assert(false, mode)
	end
	assert(ClassFactory.IsInterfaceImpl(self.__impl, ITimerImpl), mode)
end

function CTimerManager:_newSeq(tags)
	local session = self.__session
	local seq
	repeat
		session = session + 1
		if session > TIMER_SESSION_MAX then
			session = 1
		end
		seq = (session << TIMER_TYPE_SHIFT) | tags
		if self.__timers[seq] == nil then
			break
		end
		assert(session ~= self.__session, "new timer seq loop back")
	until false

	self.__session = session
	return seq
end

function CTimerManager:NewTimer(func, interval, is_repeat)
	assert(interval > 0, interval)
	local tags = TIMER_TAG_USER
	if is_repeat then
		tags = tags | TIMER_TAG_REPEAT
	end
	local seq = self:_newSeq(tags)
	local timer = {
		Date.CentiSecond() + interval,
		seq,
		interval,
		func,
	}
	self.__impl:Push(timer)
	self.__timers[seq] = timer
	return seq
end

function CTimerManager:NewSysTimer(func, interval, is_repeat)
	assert(interval > 0, interval)
	local tags = 0
	if is_repeat then
		tags = tags | TIMER_TAG_REPEAT
	end
	local seq = self:_newSeq(tags)
	local timer = {
		Date.CentiSecond() + interval,
		seq,
		interval,
		func,
	}
	self.__timers[seq] = timer
	Skynet.timeout(delay, function ()
		self:_onTimeout(seq)
	end)
	return seq
end

function CTimerManager:StopTimer(seq)
	local timer = self.__timers[seq]
	if not timer then
		return false
	end

	if (timer[TIMER_KEY_SEQ] & TIMER_TAG_USER) == TIMER_TAG_USER then
		timer[TIMER_KEY_FUNC] = nil -- 提前释放闭包，防止内存泄漏
	end
	self.__timers[seq] = false -- 释放timer对象，但保留seq占位，以防对应timeout触发前，seq分配给其他timer
	return true
end

function CTimerManager:_onTimeout(seq)
	local timer = self.__timers[seq]
	if not timer then -- stopped, remove seq
		self.__timers[seq] = nil
		return
	end

	if (timer[TIMER_KEY_SEQ] & TIMER_TAG_REPEAT) == TIMER_TAG_REPEAT then -- ticker
		local interval = timer[TIMER_KEY_INTERVAL]
		timer[TIMER_KEY_NEXT_TS] = Date.CentiSecond() + interval
		Skynet.timeout(interval, function ()
			self:_onTimeout(seq)
		end)
	else -- once timer
		self.__timers[seq] = nil
	end

	timer[TIMER_KEY_FUNC]()
end

function CTimerManager:OnTick(now)
	now = now or Date.CentiSecond()
	self.__impl:OnTick(self, now)
end

function CTimerManager:TimerNum()
	local n = 0
	for seq, timer in pairs(self.__timers) do
		if timer then
			n = n + 1
		end
	end
	return n
end

local M = {}

M.CTimerManager = CTimerManager

return M