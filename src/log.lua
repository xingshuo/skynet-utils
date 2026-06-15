local sformat = string.format
local Date = require "date"
local os_date = os.date
local Skynet = require "skynet"

local M = {}

if Skynet.getenv("logservice") == "logger" and Skynet.getenv("logger") then -- service_logger指定文件名, 会自动填充时间戳
	function M.Info(...)
		Skynet.error("[INFO] ", ...)
	end

	function M.InfoF(fmt, ...)
		Skynet.error("[INFO] ", sformat(fmt, ...))
	end

	function M.Error(...)
		Skynet.error("[ERROR] ", ...)
	end

	function M.ErrorF(fmt, ...)
		Skynet.error("[ERROR] ", sformat(fmt, ...))
	end
else
	function M.Info(...)
		local now = Date.CentiSecond()
		local timestr = os_date("%Y/%m/%d %H:%M:%S", now//100) .. sformat(".%02d", now%100)
		Skynet.error(timestr, "[INFO] ", ...)
	end
	
	function M.InfoF(fmt, ...)
		local now = Date.CentiSecond()
		local timestr = os_date("%Y/%m/%d %H:%M:%S", now//100) .. sformat(".%02d", now%100)
		Skynet.error(timestr, "[INFO] ", sformat(fmt, ...))
	end
	
	function M.Error(...)
		local now = Date.CentiSecond()
		local timestr = os_date("%Y/%m/%d %H:%M:%S", now//100) .. sformat(".%02d", now%100)
		Skynet.error(timestr, "[ERROR] ", ...)
	end
	
	function M.ErrorF(fmt, ...)
		local now = Date.CentiSecond()
		local timestr = os_date("%Y/%m/%d %H:%M:%S", now//100) .. sformat(".%02d", now%100)
		Skynet.error(timestr, "[ERROR] ", sformat(fmt, ...))
	end

end



return M