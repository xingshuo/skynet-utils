local Skynet = require "skynet"

local Now = Skynet.now
local StartTime = Skynet.starttime() -- second
local StartCentiTime = StartTime * 100

local M = {}

function M.Second()
	return StartTime + Now() // 100
end

function M.CentiSecond()
	return StartCentiTime + Now()
end

function M.MilliSecond()
	return (StartCentiTime + Now()) *10
end

return M