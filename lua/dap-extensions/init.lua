-- dap-extensions/init.lua
-- 轻量入口：require 时只定义 setup 与惰性 API 解析，不加载重模块。
-- 首次访问 M.xxx 时才 require 对应模块，并缓存到 M 表。

local M = {}

--- API 来源模块（按顺序查找；manager 优先提供核心 API，commands 提供交互式包装）
local api_sources = {
	"dap-extensions.manager",
	"dap-extensions.commands",
}

--- 解析 API 键到具体模块函数
local function resolve(key)
	-- 特殊：导出整个 commands 模块
	if key == "commands" then
		return require("dap-extensions.commands")
	end

	-- 特殊：deprecated 兼容包装
	if key == "add_inline_breakpoint" then
		return function(...)
			vim.notify("add_inline_breakpoint is deprecated, use add_column_breakpoint", vim.log.levels.WARN)
			return require("dap-extensions.manager").add_column_breakpoint(...)
		end
	end

	-- 从 manager / commands 查找
	for _, mod in ipairs(api_sources) do
		local m = require(mod)
		if m[key] then
			return m[key]
		end
	end
	return nil
end

setmetatable(M, {
	__index = function(t, key)
		local value = resolve(key)
		if value ~= nil then
			t[key] = value -- 缓存，后续访问直接命中
		end
		return value
	end,
})

function M.setup(opts)
	opts = opts or {}

	local manager = require("dap-extensions.manager")

	manager.register_type("function", require("dap-extensions.breakpoint.function"))
	manager.register_type("data", require("dap-extensions.breakpoint.data"))
	manager.register_type("instruction", require("dap-extensions.breakpoint.instruction"))
	manager.register_type("column", require("dap-extensions.breakpoint.column"))
	manager.register_type("inline", require("dap-extensions.breakpoint.column"))

	local dap = require("dap")

	dap.listeners.after.event_initialized["dap_ext"] = function(session)
		manager.on_session(session)
	end

	dap.listeners.after.event_stopped["dap_ext"] = function(session, event)
		manager.on_stopped(session, event)
	end

	if opts.ui == nil or opts.ui.sign then
		require("dap-extensions.ui.sign")
	end

	if opts.ui == nil or opts.ui.virtual_text then
		require("dap-extensions.ui.virtual_text")
	end
end

return M
