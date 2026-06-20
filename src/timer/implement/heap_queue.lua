local Skynet = require "skynet"
local Const = require "timer.const"

local TIMER_TAG_REPEAT = assert(Const.TIMER_TAG_REPEAT)

local TIMER_KEY_NEXT_TS = assert(Const.TIMER_KEY_NEXT_TS)
local TIMER_KEY_SEQ = assert(Const.TIMER_KEY_SEQ)
local TIMER_KEY_INTERVAL = assert(Const.TIMER_KEY_INTERVAL)
local TIMER_KEY_FUNC = assert(Const.TIMER_KEY_FUNC)

local function _shiftup(heap, k)
	local top = heap[k]
	repeat
		local c = k // 2
		if c <= 0 or heap[c][TIMER_KEY_NEXT_TS] <= top[TIMER_KEY_NEXT_TS] then
			break
		end
		heap[k] = heap[c]
		k = c
	until false

	heap[k] = top
end

local function _shiftdown(heap, k, size)
	local top = heap[k]
	repeat
		local c = k * 2
		if c > size then
			break
		end
		if c < size and heap[c][TIMER_KEY_NEXT_TS] > heap[c + 1][TIMER_KEY_NEXT_TS] then
			c = c + 1
		end
		if top[TIMER_KEY_NEXT_TS] <= heap[c][TIMER_KEY_NEXT_TS] then
			break
		end

		heap[k] = heap[c]
		k = c
	until false

	heap[k] = top
end

-- 基于优先队列管理用户定时器
---@class CHeapqImpl
local CHeapqImpl = DefClass("timer.CHeapqImpl")

function CHeapqImpl:_Ctor()
	self.__heap = {}
end

function CHeapqImpl:Push(timer)
	local heap = self.__heap
	local size = #heap + 1
	heap[size] = timer
	_shiftup(heap, size)
end

function CHeapqImpl:OnRemove(timer)
end

function CHeapqImpl:OnTick(manager, now)
	local heap = self.__heap
	local size = #heap
	while size > 0 do
		local timer = heap[1]
		local seq = timer[TIMER_KEY_SEQ]
		local func = timer[TIMER_KEY_FUNC]
		if not func then -- removed
			manager.__timers[seq] = nil
			heap[1] = heap[size]
			heap[size] = nil
			size = size - 1
			_shiftdown(heap, 1, size)
		elseif timer[TIMER_KEY_NEXT_TS] > now then
			break
		else
			if (seq & TIMER_TAG_REPEAT) == TIMER_TAG_REPEAT then
				timer[TIMER_KEY_NEXT_TS] = now + timer[TIMER_KEY_INTERVAL]
				_shiftdown(heap, 1, size)
			else
				manager.__timers[seq] = nil
				heap[1] = heap[size]
				heap[size] = nil
				size = size - 1
				_shiftdown(heap, 1, size)
			end
			-- should not block
			Skynet.fork(func)
		end
	end
end

local M = {}

M.CHeapqImpl = CHeapqImpl

return M