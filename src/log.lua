local sformat = string.format
local date = os.date

local M = {}

function M.Info(...)
	print(date("%Y/%m/%d %H:%M:%S"), "[INFO] ", ...)
end

function M.InfoF(fmt, ...)
	print(date("%Y/%m/%d %H:%M:%S"), "[INFO] ", sformat(fmt, ...))
end

function M.Error(...)
	print(date("%Y/%m/%d %H:%M:%S"), "[ERROR] ", ...)
end

function M.ErrorF(fmt, ...)
	print(date("%Y/%m/%d %H:%M:%S"), "[ERROR] ", sformat(fmt, ...))
end

return M