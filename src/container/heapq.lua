
local function _shiftup(heap, k)
	local top = heap[k]
	repeat
		local c = k // 2
		if c <= 0 or heap[c] <= top then
			break
		end
		heap[k] = heap[c]
		k = c
	until false

	heap[k] = top
end

-- 按元素的固定字段下标 key 比较，内联完成、无函数调用开销
local function _shiftup_key(heap, k, key)
	local top = heap[k]
	local topv = top[key]
	repeat
		local c = k // 2
		if c <= 0 or heap[c][key] <= topv then
			break
		end
		heap[k] = heap[c]
		k = c
	until false

	heap[k] = top
end

local function _shiftdown(heap, k)
	local size = #heap
	local top = heap[k]
	repeat
		local c = k * 2
		if c > size then
			break
		end
		if c < size and heap[c] > heap[c + 1] then
			c = c + 1
		end
		if top <= heap[c] then
			break
		end

		heap[k] = heap[c]
		k = c
	until false

	heap[k] = top
end

-- 按元素的固定字段下标 key 比较，内联完成、无函数调用开销
local function _shiftdown_key(heap, k, key)
	local size = #heap
	local top = heap[k]
	if top == nil then -- 堆已空（如仅剩 1 个元素时 Pop），无需下沉
		return
	end
	local topv = top[key]
	repeat
		local c = k * 2
		if c > size then
			break
		end
		if c < size and heap[c][key] > heap[c + 1][key] then
			c = c + 1
		end
		if topv <= heap[c][key] then
			break
		end

		heap[k] = heap[c]
		k = c
	until false

	heap[k] = top
end

local M = {}

-- 比较模式：设置 __key 则按该字段下标内联比较（零调用开销）；
-- 否则用标量运算符（数字直接比较）。复杂元素可通过元方法自定义比较，
-- 但需同时定义 __lt 和 __le：下沉用到 a > b（走 __lt）与 a <= b（走 __le），
-- Lua 5.4 的 __le 不会用 not(b<a) 回退，只写 __lt 会在 <= 处报错。
function M.Push(heap, item)
	local size = #heap + 1
	heap[size] = item
	local key = heap.__key
	if key then
		_shiftup_key(heap, size, key)
	else
		_shiftup(heap, size)
	end
end

function M.Pop(heap)
	local size = #heap
	if size < 1 then
		return
	end

	local top = heap[1]
	heap[1] = heap[size]
	heap[size] = nil
	local key = heap.__key
	if key then
		_shiftdown_key(heap, 1, key)
	else
		_shiftdown(heap, 1)
	end
	return top
end

-- equal to Pop() followed by Push(), but more efficient
function M.Replace(heap, item)
	local top = heap[1]
	heap[1] = item
	local key = heap.__key
	if key then
		_shiftdown_key(heap, 1, key)
	else
		_shiftdown(heap, 1)
	end
	return top
end

function M.Pushpop(heap, item)
	if #heap < 1 then
		return item
	end
	local key = heap.__key
	if key then
		if item[key] > heap[1][key] then
			item, heap[1] = heap[1], item
			_shiftdown_key(heap, 1, key)
		end
	else
		if item > heap[1] then
			item, heap[1] = heap[1], item
			_shiftdown(heap, 1)
		end
	end
	return item
end

-- Transform list into a heap
function M.Heapify(heap)
	local key = heap.__key
	if key then
		for i = 1, #heap do
			_shiftup_key(heap, i, key)
		end
	else
		for i = 1, #heap do
			_shiftup(heap, i)
		end
	end
end

return M