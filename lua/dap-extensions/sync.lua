-- dap-extensions/sync.lua
-- 与 adapter 同步断点。列表型断点（function/data/instruction）采用整表替换语义；
-- column 断点与 nvim-dap 原生行断点合并后走同一个 setBreakpoints 请求。

local registry = require("dap-extensions.registry")
local resolver = require("dap-extensions.resolver")
local sign = require("dap-extensions.ui.sign")
local Event = require("dap-extensions.event")

local M = {}

if sign then
	if not sign.update_sign then
		sign.update_sign = sign.show_sign or function() end
	end
end

local sync_handlers = {}

-- 已经向 adapter 发过请求的类型（用于“删除最后一个断点后发空列表清理”）
local synced_types = {}

-- 已经同步过 column 断点的 source path（用于删除最后一个 column 后清理 adapter 端）
local column_synced_sources = {}

function M.register_handler(breakpoint_type, handler)
	sync_handlers[breakpoint_type] = handler
end

---------------------------------------------------------------------
-- 状态更新 helper
---------------------------------------------------------------------
local function set_status(bp, status)
	local old = bp.status
	if old == status then
		return
	end
	bp.status = status
	sign.update_sign(bp)
	Event.emit("breakpoint_status_changed", bp)
end

---------------------------------------------------------------------
-- function breakpoints
---------------------------------------------------------------------
local function sync_function_breakpoints(session, bps)
	synced_types["function"] = true

	local breakpoints = {}
	for _, bp in ipairs(bps) do
		local def = { name = bp.config.function_name }
		if bp.config.condition and bp.config.condition ~= "" then
			def.condition = bp.config.condition
		end
		if bp.config.hitCondition and bp.config.hitCondition ~= "" then
			def.hitCondition = bp.config.hitCondition
		end
		table.insert(breakpoints, def)
	end

	session:request("setFunctionBreakpoints", { breakpoints = breakpoints }, function(err, resp)
		if err then
			for _, bp in ipairs(bps) do
				set_status(bp, "rejected")
			end
			return
		end

		if resp and resp.breakpoints then
			for i, bp_resp in ipairs(resp.breakpoints) do
				local bp = bps[i]
				if bp then
					if bp_resp.verified then
						if bp_resp.id then
							registry.link(bp_resp.id, bp)
						end
						set_status(bp, "verified")
					else
						set_status(bp, "rejected")
					end
					Event.emit("breakpoint_changed", bp)
				end
			end
		end
	end)
end

M.register_handler("function", sync_function_breakpoints)

---------------------------------------------------------------------
-- data breakpoints
---------------------------------------------------------------------
local function make_data_def(bp)
	local def = {
		dataId = bp.dataId,
		accessType = bp.config.accessType or "write",
	}
	if bp.config.condition and bp.config.condition ~= "" then
		def.condition = bp.config.condition
	end
	if bp.config.hitCondition and bp.config.hitCondition ~= "" then
		def.hitCondition = bp.config.hitCondition
	end
	return def
end

local function sync_data_breakpoints(session, event, bps)
	-- 空列表：清理 adapter 端
	if #bps == 0 then
		if synced_types.data then
			session:request("setDataBreakpoints", { breakpoints = {} }, function() end)
		end
		return
	end

	local frame = resolver.get_current_frame(session, event)
	if not frame then
		-- 没有栈帧无法解析 dataId；保持 pending，等下一次 event_stopped 再试
		return
	end
	local frameId = frame.id

	synced_types.data = true

	local pending = #bps
	local defs = {}

	local function finish()
		pending = pending - 1
		if pending ~= 0 then
			return
		end

		session:request("setDataBreakpoints", { breakpoints = defs }, function(err, resp)
			if err then
				for _, bp in ipairs(bps) do
					if bp.status == "pending" then
						set_status(bp, "rejected")
					end
				end
				return
			end

			if resp and resp.breakpoints then
				for i, bp_resp in ipairs(resp.breakpoints) do
					local def = defs[i]
					if def then
						local bp = registry.resolve(def.dataId)
						if bp then
							if bp_resp.verified then
								set_status(bp, "verified")
							else
								set_status(bp, "rejected")
							end
							Event.emit("breakpoint_changed", bp)
						end
					end
				end
			end
		end)
	end

	for _, bp in ipairs(bps) do
		if bp.dataId then
			table.insert(defs, make_data_def(bp))
			finish()
		else
			session:request("dataBreakpointInfo", {
				name = bp.config.expression,
				frameId = frameId,
			}, function(err, resp)
				if err or not resp or not resp.dataId then
					set_status(bp, "rejected")
				else
					bp.dataId = resp.dataId
					registry.link(resp.dataId, bp)
					table.insert(defs, make_data_def(bp))
				end
				finish()
			end)
		end
	end
end

M.register_handler("data", sync_data_breakpoints)

---------------------------------------------------------------------
-- instruction breakpoints
---------------------------------------------------------------------
local function sync_instruction_breakpoints(session, bps)
	synced_types.instruction = true

	local breakpoints = {}
	for _, bp in ipairs(bps) do
		local def = {
			instructionReference = bp.config.instruction_reference,
			offset = bp.config.offset or 0,
		}
		if bp.config.condition and bp.config.condition ~= "" then
			def.condition = bp.config.condition
		end
		if bp.config.hitCondition and bp.config.hitCondition ~= "" then
			def.hitCondition = bp.config.hitCondition
		end
		if bp.config.accessType then
			def.accessType = bp.config.accessType
		end
		if bp.config.size then
			def.size = bp.config.size
		end
		table.insert(breakpoints, def)
	end

	session:request("setInstructionBreakpoints", { breakpoints = breakpoints }, function(err, resp)
		if err then
			for _, bp in ipairs(bps) do
				set_status(bp, "rejected")
			end
			return
		end

		if resp and resp.breakpoints then
			for i, bp_resp in ipairs(resp.breakpoints) do
				local bp = bps[i]
				if bp then
					if bp_resp.verified then
						if bp_resp.id then
							registry.link(bp_resp.id, bp)
						end
						set_status(bp, "verified")
					else
						set_status(bp, "rejected")
					end
					Event.emit("breakpoint_changed", bp)
				end
			end
		end
	end)
end

M.register_handler("instruction", sync_instruction_breakpoints)

---------------------------------------------------------------------
-- column breakpoints（与 nvim-dap 原生行断点合并，避免互相覆盖）
---------------------------------------------------------------------
local function sync_column_breakpoints(session, bps)
	local dap_breakpoints = require("dap.breakpoints")

	-- 按源文件分组
	local by_path = {}
	for _, bp in ipairs(bps) do
		local bufnr = bp.config.bufnr
		if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
			local path = vim.api.nvim_buf_get_name(bufnr)
			if path and path ~= "" then
				by_path[path] = by_path[path] or { bufnr = bufnr, columns = {} }
				table.insert(by_path[path].columns, bp)
			end
		end
	end

	-- 之前同步过、但现在已无 column 断点的源：发一次“仅原生”以清理 adapter 端 column
	for path in pairs(column_synced_sources) do
		if not by_path[path] then
			local bufnr = vim.fn.bufnr(path, true)
			if bufnr ~= -1 then
				by_path[path] = { bufnr = bufnr, columns = {} }
			end
		end
	end

	for path, src in pairs(by_path) do
		local bufnr = src.bufnr
		if vim.api.nvim_buf_is_loaded(bufnr) then
			local breakpoints = {}

			-- 1) 合并 nvim-dap 原生行断点
			local native = dap_breakpoints.get(bufnr)[bufnr] or {}
			for _, nb in ipairs(native) do
				local def = { line = nb.line }
				if nb.condition and nb.condition ~= "" then
					def.condition = nb.condition
				end
				if nb.hitCondition and nb.hitCondition ~= "" then
					def.hitCondition = nb.hitCondition
				end
				if nb.logMessage and nb.logMessage ~= "" then
					def.logMessage = nb.logMessage
				end
				table.insert(breakpoints, def)
			end

			-- 2) column 断点
			for _, bp in ipairs(src.columns) do
				local def = { line = bp.config.line }
				if bp.config.column then
					def.column = bp.config.column
				end
				if bp.config.condition and bp.config.condition ~= "" then
					def.condition = bp.config.condition
				end
				if bp.config.hitCondition and bp.config.hitCondition ~= "" then
					def.hitCondition = bp.config.hitCondition
				end
				table.insert(breakpoints, def)
			end

			local native_count = #native

			session:request("setBreakpoints", {
				source = { path = path },
				breakpoints = breakpoints,
			}, function(err, resp)
				if err then
					for _, bp in ipairs(src.columns) do
						set_status(bp, "rejected")
					end
					return
				end

				if resp and resp.breakpoints then
					for i, bp_resp in ipairs(resp.breakpoints) do
						if i <= native_count then
							-- 原生断点：把 verified 状态交还给 nvim-dap
							local nb = native[i]
							if nb then
								dap_breakpoints.set_state(bufnr, {
									id = bp_resp.id,
									line = nb.line,
									verified = bp_resp.verified,
									message = bp_resp.message,
								})
							end
						else
							local col = src.columns[i - native_count]
							if col then
								if bp_resp.verified then
									if bp_resp.id then
										registry.link(bp_resp.id, col)
									end
									set_status(col, "verified")
								else
									set_status(col, "rejected")
								end
								Event.emit("breakpoint_changed", col)
							end
						end
					end
				end
			end)
		end
	end

	-- 更新已同步的 column 源集合
	column_synced_sources = {}
	for path, src in pairs(by_path) do
		if #src.columns > 0 then
			column_synced_sources[path] = true
		end
	end
end

M.register_handler("column", sync_column_breakpoints)

---------------------------------------------------------------------
-- 全量同步：发送所有启用断点的完整列表（列表替换语义）
---------------------------------------------------------------------
function M.sync(session, event)
	if not session then
		return
	end

	local grouped = {}
	for _, bp in pairs(registry.bps) do
		if bp.enabled ~= false then
			grouped[bp.type] = grouped[bp.type] or {}
			table.insert(grouped[bp.type], bp)
		end
	end

	-- 列表型断点：有内容时发送；曾经发过时也要发送（空列表用于清理）
	for _, bp_type in ipairs({ "function", "data", "instruction" }) do
		local bps = grouped[bp_type]
		if (bps and #bps > 0) or synced_types[bp_type] then
			local handler = sync_handlers[bp_type]
			if handler then
				handler(session, bps or {}, event)
			end
		end
	end

	-- column：始终走一遍（内部用 column_synced_sources 判断是否需要清理）
	local column_handler = sync_handlers.column
	if column_handler then
		column_handler(session, grouped.column or {}, event)
	end
end

function M.resync(session, event)
	if not session then
		return
	end
	for _, bp in pairs(registry.bps) do
		if bp.status == "verified" or bp.status == "hit" then
			bp.status = "pending"
		end
	end
	M.sync(session, event)
end

function M.clear_all(session)
	if not session then
		registry.bps = {}
		registry.map = {}
		column_synced_sources = {}
		synced_types = {}
		return
	end

	for bp_type in pairs(sync_handlers) do
		if bp_type == "function" then
			session:request("setFunctionBreakpoints", { breakpoints = {} }, function() end)
		elseif bp_type == "data" then
			session:request("setDataBreakpoints", { breakpoints = {} }, function() end)
		elseif bp_type == "instruction" then
			session:request("setInstructionBreakpoints", { breakpoints = {} }, function() end)
		end
	end

	registry.bps = {}
	registry.map = {}
	column_synced_sources = {}
	synced_types = {}
end

function M.get_registered_types()
	local types = {}
	for t in pairs(sync_handlers) do
		table.insert(types, t)
	end
	return types
end

return M
