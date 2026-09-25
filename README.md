# nvim-dap-extensions

自定义 DAP 断点扩展（个人插件）。在 [nvim-dap](https://github.com/mfussenegger/nvim-dap) 基础上补充四类断点：

- **function** — 函数断点（`setFunctionBreakpoints`）
- **data** — 数据断点（`dataBreakpointInfo` + `setDataBreakpoints`）
- **instruction** — 硬件断点（`setInstructionBreakpoints`，execute / read / write / readWrite）
- **column** — 列断点（`setBreakpoints` + `column`，会与 nvim-dap 原生行断点合并发送）

## 安装（lazy.nvim）

```lua
{
    dir = "~/neovim-plugins/nvim-dap-extensions",
    name = "nvim-dap-extensions",
    dev = true,
    lazy = true,
}
```

建议把它作为 `nvim-dap` 和 `nvim-dap-view` 的依赖：

```lua
dependencies = { "nvim-dap-extensions" },
```

## 使用

```lua
require("dap-extensions").setup({
    ui = {
        sign = true,          -- 显示 sign 标记
        virtual_text = true,  -- 显示虚拟文本
    },
})
```

## 与 nvim-dap-view 集成

在 `nvim-dap-view` 的 setup 里：

```lua
render = {
    breakpoints = {
        get_extra = require("dap-extensions.integration").get_view_entries,
    },
},
```

断点视图会显示为 `● [fn] 函数名 | 路径 | 行号` 这类条目，删除键会走 `remove` 回调。
