local Base = require("dap-extensions.breakpoint.base")

local M = setmetatable({}, { __index = Base })

function M:new(cfg)
	local o = Base.new(self, cfg)
	o.type = "data"
	o.config.expression = cfg.expression
	o.config.accessType = cfg.accessType or "write"
	o.config.condition = cfg.condition
	o.config.hitCondition = cfg.hitCondition
	return o
end

return M
