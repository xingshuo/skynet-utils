local Const = require "timer.const"
local IntervalQueue = require "timer.implement.interval_queue"
local HeapQueue = require "timer.implement.heap_queue"

local TIMER_KEY_INTERVAL = assert(Const.TIMER_KEY_INTERVAL)

-- 短/长分界默认 15s。注意单位是 centisecond(Date.CentiSecond)，15s = 1500。
-- 取 15s 而非更大值：游戏里 sub-15s 才是"少种类+超高频"(战斗tick/短CD)，必须留短桶吃 O(1)；
-- 过了 15s interval 种类开始发散且触发稀疏，丢给 heap(idle 免费、不怕种类) 更省，且规避短桶组数爆炸。
local DEFAULT_THRESHOLD = 1500

-- 混合实现：按 interval 量级把定时器静态路由到两个子实现，吃满游戏定时器的"双峰分布"。
--   短桶(interval_queue)：少种类、高频短 repeat(技能CD/buff/战斗tick)，O(1) FIFO 单价最低；
--   长桶(heap)           ：大量互异远期一次性/低频 timer(离线奖励/建造/活动)，idle 近乎免费，
--                          且不随 interval 种类退化(单 interval_queue 会被长期 timer 的海量空组拖垮)。
-- 路由轴取 interval(静态)，timer 一旦入桶终身不迁移，无需跨桶搬迁。
-- 两子实现共享 manager.__timers 且都遵循"func=nil 惰性删除 + OnRemove no-op"契约，
-- seq 由 manager 全局分配天然唯一，两桶互不干扰。
---@class CHybridImpl
local CHybridImpl = DefClass("timer.CHybridImpl")

-- threshold: interval <= threshold 进短桶，否则进长桶；缺省 DEFAULT_THRESHOLD(15s)。
function CHybridImpl:_Ctor(threshold)
	self.__threshold = threshold or DEFAULT_THRESHOLD
	self.__short = IntervalQueue.CIntervalQueueImpl:New()
	self.__long = HeapQueue.CHeapqImpl:New()
end

function CHybridImpl:Push(timer)
	if timer[TIMER_KEY_INTERVAL] <= self.__threshold then
		self.__short:Push(timer)
	else
		self.__long:Push(timer)
	end
end

function CHybridImpl:OnRemove(timer)
	-- 当前两桶 OnRemove 均为 no-op；仍按 interval 路由，便于将来某桶启用主动删除。
	if timer[TIMER_KEY_INTERVAL] <= self.__threshold then
		self.__short:OnRemove(timer)
	else
		self.__long:OnRemove(timer)
	end
end

function CHybridImpl:OnTick(manager, now)
	self.__short:OnTick(manager, now)
	self.__long:OnTick(manager, now)
end

local M = {}

M.CHybridImpl = CHybridImpl

return M
