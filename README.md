# nvim-dap-extensions

Custom DAP breakpoint extensions (personal plugin). Adds four breakpoint types
on top of [nvim-dap](https://github.com/mfussenegger/nvim-dap):

- **function** — function breakpoints (`setFunctionBreakpoints`)
- **data** — data breakpoints (`dataBreakpointInfo` + `setDataBreakpoints`)
- **instruction** — hardware breakpoints (`setInstructionBreakpoints`,
  execute / read / write / readWrite)
- **column** — column breakpoints (`setBreakpoints` + `column`, merged with
  nvim-dap's native line breakpoints)

[中文文档](README.zh.md)

## Installation

With lazy.nvim:

```lua
{
    "huayue5201/nvim-dap-extensions.nvim",
    name = "nvim-dap-extensions",
    lazy = true,
}
```

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/huayue5201/nvim-dap-extensions.nvim" })
```

It is recommended to add it as a dependency of `nvim-dap` and
`nvim-dap-view`:

```lua
dependencies = { "nvim-dap-extensions" },
```

## Usage

```lua
require("dap-extensions").setup({
    ui = {
        sign = true,          -- show sign markers
        virtual_text = true,  -- show virtual text
    },
})
```

## Lua API

```lua
local ext = require("dap-extensions")

ext.add_function_breakpoint()
ext.add_data_breakpoint()
ext.add_hardware_execute_breakpoint()  -- execute / read / write / readWrite
ext.add_hardware_read_breakpoint()
ext.add_hardware_write_breakpoint()
ext.add_hardware_access_breakpoint()
ext.add_column_breakpoint()
ext.quick_column_breakpoint()
ext.list_breakpoints()
ext.clear_breakpoints()
ext.delete_breakpoint_at_current_line()
ext.toggle_breakpoint_deletion()
ext.toggle_breakpoint_enabled()
```

> `add_inline_breakpoint` is deprecated; use `add_column_breakpoint` instead.

## Integration with nvim-dap-view

In `nvim-dap-view`'s setup:

```lua
render = {
    breakpoints = {
        get_extra = require("dap-extensions.integration").get_view_entries,
    },
},
```

Breakpoint entries render as `● [fn] function_name | path | line`, and the
delete key goes through the `remove` callback.

## License

MIT License
