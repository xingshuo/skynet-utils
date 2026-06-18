local assert = assert
local ipairs = ipairs

---@class CLevelWheel
local CLevelWheel = DefClass("CLevelWheel")

function CLevelWheel:_Ctor(size)
	self.__slots = {}
	for i = 1, size do
		self.__slots[i] = {}
	end
	self.__size = size
	self.__next = 1
end

function CLevelWheel:PushNode(node, delta)
	local idx = (self.__next + delta - 2) % self.__size + 1
	local list = self.__slots[idx]
	list[#list + 1] = node
end

function CLevelWheel:Tick()
	local cur = self.__next
	local list = self.__slots[cur]
	self.__next = cur % self.__size + 1
	if list[1] then
		self.__slots[cur] = {}
		return list
	end
end


---@class CTimingWheel
local CTimingWheel = DefClass("CTimingWheel")

-- expireIdx：节点须在该字段下标携带自己的绝对到期 tick，容器据此做级联重挂载。
-- 由调用方拥有节点和该字段，容器直接存节点引用，免去包装表的分配。
function CTimingWheel:_Ctor(levelList, expireIdx)
	local n = #levelList
	assert(n > 0)
	assert(expireIdx, "expireIdx required")
	self.__expire_idx = expireIdx
	self.__wheels = {}
	for i, size in ipairs(levelList) do
		assert(size > 0)
		self.__wheels[i] = CLevelWheel:New(size)
	end
	self.__level_num = n
	self.__ranges = {}
	self.__far = {} -- beyond wheels range
	local upper = 1
	for i, wheel in ipairs(self.__wheels) do
		upper = upper * wheel.__size
		self.__ranges[i] = upper
	end
	self.__tick = 0
end

function CTimingWheel:_pushNode(node)
	local delta = node[self.__expire_idx] - self.__tick
	assert(delta > 0)
	local expire = self.__wheels[1].__next + delta - 1
	for i, wheel in ipairs(self.__wheels) do
		if expire <= self.__ranges[i] then
			if i == 1 then
				wheel:PushNode(node, delta)
			else
				wheel:PushNode(node, (expire - 1)//self.__ranges[i-1])
			end
			return i
		end
	end
	local list = self.__far
	list[#list + 1] = node
	return -1
end

function CTimingWheel:_shift()
	self.__tick = self.__tick + 1
	for i, wheel in ipairs(self.__wheels) do
		if wheel.__next ~= 1 then
			break
		end
		if i == self.__level_num then
			local moveList = self.__far
			if moveList[1] then
				self.__far = {}
				for _, node in ipairs(moveList) do
					self:_pushNode(node)
				end
			end
		else
			local moveList = self.__wheels[i+1]:Tick()
			if moveList then
				for _, node in ipairs(moveList) do
					self:_pushNode(node)
				end 
			end
		end
	end
end

-- node 即调用方对象本身（无包装表）；容器把绝对到期 tick 写入 node[expireIdx]。
function CTimingWheel:Push(node, delta)
	assert(delta > 0)
	node[self.__expire_idx] = self.__tick + delta
	return self:_pushNode(node)
end

function CTimingWheel:Update(outList)
	local timeouts = self.__wheels[1]:Tick()
	self:_shift()
	if not timeouts then
		return 0
	end
	for i, node in ipairs(timeouts) do
		outList[i] = node
	end
	return #timeouts
end

function CTimingWheel:GetTick()
	return self.__tick
end

local M = {}

M.CTimingWheel = CTimingWheel

return M