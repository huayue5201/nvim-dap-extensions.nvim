-- breakpoint/function.lua
local Base = require("dap-extensions.breakpoint.base")

local M = setmetatable({}, { __index = Base })

function M:new(cfg)
	local o = Base.new(self, cfg)
	o.type = "function"
	-- 将特定字段也放到 config 中统一管理
	o.config.function_name = cfg.function_name
	o.config.condition = cfg.condition
	o.config.hitCondition = cfg.hitCondition

	return o
end

return M
