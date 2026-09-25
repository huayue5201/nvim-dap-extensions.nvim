-- dap-extensions/integration.lua
--
-- 将自定义断点（function / data / instruction / column）接入 nvim-dap-view 的 breakpoints 视图。
--
-- 接入方式：在 nvim-dap-view 的 setup 里配置
--   render = { breakpoints = { get_extra = require("dap-extensions.integration").get_view_entries } }
--
-- 本模块不依赖 nvim-dap-view 被加载；nvim-dap-view 通过 get_extra 回调懒加载本模块，
-- 刷新监听也只在第一次渲染时注册。

local M = {}

local listeners_registered = false

local function build_parts(bp)
	local cfg = bp.config or {}

	local type_label = ({
		["function"] = "fn",
		["data"] = "data",
		["instruction"] = "hw",
		["column"] = "col",
	})[bp.type] or bp.type

	local detail = ""

	if bp.type == "function" then
		detail = cfg.function_name or ""
	elseif bp.type == "data" then
		detail = cfg.expression or ""
		if cfg.accessType and cfg.accessType ~= "write" then
			detail = detail .. " (" .. cfg.accessType .. ")"
		end
	elseif bp.type == "instruction" then
		detail = cfg.instruction_reference or ""
		if cfg.accessType then
			detail = detail .. " " .. cfg.accessType
		end
	elseif bp.type == "column" then
		detail = "line " .. tostring(cfg.line) .. " col " .. tostring(cfg.column)
	end

	local extras = {}
	if cfg.condition and cfg.condition ~= "" then
		table.insert(extras, "if " .. cfg.condition)
	end
	if cfg.hitCondition and cfg.hitCondition ~= "" then
		table.insert(extras, "hit " .. cfg.hitCondition)
	end
	if #extras > 0 then
		detail = detail .. " [" .. table.concat(extras, ", ") .. "]"
	end

	local icon = "●"
	local detail_hl = "Special"

	if bp.enabled == false then
		icon = "○"
		detail_hl = "Comment"
	elseif bp.status == "rejected" then
		icon = "✗"
		detail_hl = "DiagnosticError"
	elseif bp.status == "pending" then
		icon = "◌"
		detail_hl = "Comment"
	end

	local text = icon .. " [" .. type_label .. "] " .. detail

	local has_location = bp.config
		and bp.config.bufnr
		and bp.config.line
		and vim.api.nvim_buf_is_loaded(bp.config.bufnr)

	if not has_location then
		return {
			{ text = text, hl = detail_hl },
		}
	end

	local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bp.config.bufnr), ":.")

	return {
		{ text = path, hl = "FileName" },
		{ text = tostring(bp.config.line), hl = "LineNumber" },
		{ text = text, hl = detail_hl },
	}
end

--- 注册自定义断点事件监听：断点视图打开时实时刷新
function M.ensure_listeners()
	if listeners_registered then
		return
	end
	listeners_registered = true

	local ok, event = pcall(require, "dap-extensions.event")
	if not ok or not event.on then
		return
	end

	local refresh = function()
		vim.schedule(function()
			local ok_state, state = pcall(require, "dap-view.state")
			if not ok_state or state.current_section ~= "breakpoints" then
				return
			end

			local ok_views, views = pcall(require, "dap-view.views")
			if ok_views and views.switch_to_view then
				views.switch_to_view("breakpoints")
			end
		end)
	end

	for _, ev in ipairs({
		"breakpoint_created",
		"breakpoint_deleted",
		"breakpoint_changed",
		"breakpoint_status_changed",
		"breakpoint_location_updated",
		"breakpoint_enabled_changed",
		"breakpoints_cleared",
	}) do
		event.on(ev, refresh)
	end
end

--- 由 nvim-dap-view 调用：返回自定义断点条目列表
--- @return dapview.ExtraBreakpointEntry[]
function M.get_view_entries()
	M.ensure_listeners()

	local ok, manager = pcall(require, "dap-extensions.manager")
	if not ok or not manager.list_breakpoints then
		return {}
	end

	local ok_list, bps = pcall(manager.list_breakpoints)
	if not ok_list then
		return {}
	end

	local entries = {}
	for _, bp in ipairs(bps) do
		local entry = {
			parts = build_parts(bp),
			remove = function()
				manager.remove_breakpoint(bp.id)
			end,
		}

		if bp.config and bp.config.bufnr and bp.config.line then
			entry.path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bp.config.bufnr), ":.")
			entry.lnum = bp.config.line
		end

		table.insert(entries, entry)
	end

	return entries
end

-- 兼容旧命名
M.get_extra_breakpoints = M.get_view_entries

return M
