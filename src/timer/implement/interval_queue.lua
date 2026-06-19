local Skynet = require "skynet"
local Const = require "timer.const"

local TIMER_TAG_REPEAT = assert(Const.TIMER_TAG_REPEAT)

local TIMER_KEY_NEXT_TS = assert(Const.TIMER_KEY_NEXT_TS)
local TIMER_KEY_SEQ = assert(Const.TIMER_KEY_SEQ)
local TIMER_KEY_INTERVAL = assert(Const.TIMER_KEY_INTERVAL)
local TIMER_KEY_FUNC = assert(Const.TIMER_KEY_FUNC)

local MAX_TS = math.maxinteger

-- 按触发间隔(interval)分组的 FIFO 队列管理用户定时器：每个 interval 一条队列，
-- 同 interval 的 timer 按启动顺序入队即按到期时间升序，故每 tick 只需检查各队队头。
-- 注：repeat 稳态下分组队列的 h/t 会持续右移，[1..h-1] 置 nil 的死前缀由 Lua 的
-- rehash 回收（数组/哈希段按活跃 key 数收敛，不会无界增长），无需手动整理。
---@class CIntervalQueueImpl
local CIntervalQueueImpl = DefClass("timer.CIntervalQueueImpl")

function CIntervalQueueImpl:_Ctor()
	self.__groups = {} -- interval : timer queue
	self.__min_ts = MAX_TS
end

function CIntervalQueueImpl:Push(timer)
	local interval = timer[TIMER_KEY_INTERVAL]
	local queue = self.__groups[interval]
	if not queue then
		self.__groups[interval] = {timer, h = 1, t = 1}
		local next_ts = timer[TIMER_KEY_NEXT_TS]
		if next_ts < self.__min_ts then
			self.__min_ts = next_ts
		end
	else
		local t = queue.t + 1
		queue.t = t
		queue[t] = timer
	end
end

function CIntervalQueueImpl:OnRemove(timer)
end

function CIntervalQueueImpl:OnTick(manager, now)
	local min_ts = self.__min_ts
	if min_ts > now then
		return
	end

	min_ts = MAX_TS
	for interval, queue in pairs(self.__groups) do
		while true do
			if queue.h == queue.t + 1 then -- queue empty
				self.__groups[interval] = nil
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
				goto continue
			end
			local next_ts = timer[TIMER_KEY_NEXT_TS]
			if next_ts > now then
				if next_ts < min_ts then
					min_ts = next_ts
				end
				break
			end
			queue[h] = nil
			queue.h = h + 1
			if (seq & TIMER_TAG_REPEAT) == TIMER_TAG_REPEAT then
				next_ts = now + interval
				timer[TIMER_KEY_NEXT_TS] = next_ts
				if next_ts < min_ts then
					min_ts = next_ts
				end
				local t = queue.t + 1
				queue.t = t
				queue[t] = timer
			else
				manager.__timers[seq] = nil
			end
			-- should not block
			Skynet.fork(func)
			::continue::
		end
	end
	self.__min_ts = min_ts
end

local M = {}

M.CIntervalQueueImpl = CIntervalQueueImpl

return M