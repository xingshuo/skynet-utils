
local sformat = string.format
local getmetatable = getmetatable

local META_CLASS_NAME = "MetaClass"

---@class MetaClass
local metaClass = {}
metaClass.__index = metaClass
metaClass._classType = META_CLASS_NAME
metaClass._parentType = nil
metaClass._subclassTypes = {}

local classPool = {}
classPool[META_CLASS_NAME] = metaClass

function metaClass:_Ctor()

end

function metaClass:_Dispose()

end

function metaClass:New(...)
	local obj = {}
	setmetatable(obj, self)
	obj:_Ctor(...)
	return obj
end

function metaClass:Delete()
	self:_Dispose()
end


local function _defaultToString(obj)
	local ctype = obj._classType
	local originMeta = getmetatable(obj)
	setmetatable(obj, nil)
	local str = sformat("[ctype:%s].%s", ctype, obj)
	setmetatable(obj, originMeta)
	return str
end

function DefClass(clsType, parentCls)
	parentCls = parentCls or classPool[META_CLASS_NAME]
	local parentType = parentCls._classType
	assert(classPool[parentType], parentType)

	local class = classPool[clsType]
	if class then
		assert(class._parentType == parentType, parentType)
		return class
	end

	class = {}
	class.__index = class
	class.__tostring = _defaultToString

	class._classType = clsType
	class._parentType = parentType
	class._subclassTypes = {}
	setmetatable(class, parentCls)
	classPool[clsType] = class
	parentCls._subclassTypes[clsType] = true

	return class
end


local M = {}

function M.Super(cls)
	local mt = getmetatable(cls)
	return mt and mt.__index
end

function M.GetClass(clsType)
	local class = assert(classPool[clsType], clsType)
	return class
end

function M.IsInstance(obj, clsType)
	return obj._classType == clsType
end

function M.IsInterfaceImpl(obj, interface)
	for method in pairs(interface) do
		if type(obj[method]) ~= 'function' then
			return false
		end
	end
	return true
end

return M