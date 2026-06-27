
local M = {}

M.TIMER_IMPL = {
	HASHED_WHEEL = 1, -- 单层时间轮
	HEAP_QUEUE = 2,
	INTERVAL_QUEUE = 3, -- 按触发间隔分组的 FIFO 队列
	SIMPLE = 4,
	TIMING_WHEEL = 5, -- 多层时间轮
	HYBRID = 6, -- 混合：按 interval 量级路由到短桶(interval_queue)/长桶(heap)
}

M.TIMER_KEY_NEXT_TS = 1
M.TIMER_KEY_SEQ = 2
M.TIMER_KEY_INTERVAL = 3
M.TIMER_KEY_FUNC = 4

local SESSION_SHIFT = 30
M.TIMER_SESSION_MASK = (1 << SESSION_SHIFT) - 1
M.TIMER_TAG_USER = 1 << SESSION_SHIFT
M.TIMER_TAG_REPEAT = 2 << SESSION_SHIFT

return M