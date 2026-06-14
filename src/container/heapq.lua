
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

local function _shiftup_ex(heap, k, le_cmp)
	local top = heap[k]
	repeat
		local c = k // 2
		if c <= 0 or le_cmp(heap[c], top) then
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

local function _shiftdown_ex(heap, k, le_cmp)
	local size = #heap
	local top = heap[k]
	repeat
		local c = k * 2
		if c > size then
			break
		end
		if c < size and not le_cmp(heap[c], heap[c + 1]) then
			c = c + 1
		end
		if le_cmp(top, heap[c]) then
			break
		end

		heap[k] = heap[c]
		k = c
	until false

	heap[k] = top
end

local M = {}

function M.Push(heap, item)
	local size = #heap + 1
	heap[size] = item
	if heap.__le_cmp then
		_shiftup_ex(heap, size, heap.__le_cmp)
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
	if heap.__le_cmp then
		_shiftdown_ex(heap, 1, heap.__le_cmp)
	else
		_shiftdown(heap, 1)
	end
	return top
end

-- equal to Pop() followed by Push(), but more efficient
function M.Replace(heap, item)
	local top = heap[1]
	heap[1] = item
	if heap.__le_cmp then
		_shiftdown_ex(heap, 1, heap.__le_cmp)
	else
		_shiftdown(heap, 1)
	end
	return top
end

function M.Pushpop(heap, item)
	if #heap < 1 then
		return item
	end
	local le_cmp = heap.__le_cmp
	if le_cmp then
		if not le_cmp(item, heap[1]) then
			item, heap[1] = heap[1], item
			_shiftdown_ex(heap, 1, le_cmp)
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
	local le_cmp = heap.__le_cmp
	if le_cmp then
		for i = 1, #heap do
			_shiftup_ex(heap, i, le_cmp)
		end
	else
		for i = 1, #heap do
			_shiftup(heap, i)
		end
	end
end

return M