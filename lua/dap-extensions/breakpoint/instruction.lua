-- dap-extensions/breakpoint/instruction.lua
local Base = require("dap-extensions.breakpoint.base")

local M = setmetatable({}, { __index = Base })

function M:new(cfg)
	local o = Base.new(self, cfg)
	o.type = "instruction"

	o.config.instruction_reference = cfg.instruction_reference
	o.config.offset = cfg.offset or 0
	o.config.accessType = cfg.accessType or "execute" -- execute, read, write
	o.config.size = cfg.size or 1 -- 监控的内存大小（字节）
	o.config.condition = cfg.condition
	o.config.hitCondition = cfg.hitCondition

	return o
end

return M
