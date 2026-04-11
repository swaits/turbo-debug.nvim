# tiny-debugger.nvim

A zero-config debugging experience for Neovim 0.12+. One line of config, full
IDE-class debugging: inline variable values, hover inspection, persistent
breakpoints, watch expressions, and modal keybindings that just work.

## Install

```lua
vim.pack.add("swaits/tiny-debugger.nvim")
```

That's it. No other config needed.

## What You Get

- **Inline virtual text** — variable values appear right in your source code,
  updated live as you step
- **Hover inspection** — press `K` on any expression to see its value
- **Persistent breakpoints** — survive Neovim restarts, visible in the sign
  column at all times
- **Watch expressions** — press `W` to add the expression under your cursor
- **Scopes panel** — all local/global variables in the current frame
- **Stack traces** — navigate the call stack, jump to any frame
- **REPL** — evaluate arbitrary expressions in the debug context
- **Console** — program stdout/stderr
- **Modal keybindings** — single-key controls, active only during debug sessions
- **Help box** — shows all keybindings, re-openable with `?`
- **Zero-config adapters** for 10+ languages

## UI Layout

```
┌──────────────────────────────────┬──────────────────┐
│                                  │ Scopes     (50%) │
│          Source Code              │                  │
│                                  ├──────────────────┤
│     x = 42  -- « virtual text    │ Watches    (25%) │
│                                  ├──────────────────┤
│                                  │ Stacks     (25%) │
├──────────────────────────────────┴──────────────────┤
│ REPL (50%)               │ Console (50%)            │
└──────────────────────────┴──────────────────────────┘
```

## Keybindings

`<leader>d` toggles debug mode. During debug mode:

| Key | Action                 | Mnemonic            |
|-----|------------------------|---------------------|
| `c` | Continue               | Continue            |
| `s` | Step over              | Step                |
| `d` | Step into              | Descend             |
| `r` | Step out               | Return              |
| `C` | Run to cursor          | Continue to cursor  |
| `x` | Toggle breakpoint      | X marks the spot    |
| `X` | Conditional breakpoint | Shift-x             |
| `W` | Watch expression       | Watch               |
| `K` | Hover / inspect        | LSP hover convention|
| `E` | Eval in REPL           | Evaluate            |
| `q` | Terminate session      | Quit                |
| `R` | Restart session        | Rerun               |
| `?` | Help popup             | Help                |

`x` and `X` work outside debug mode too.

All navigation keys preserved: `h j k l w b e f / n` etc.

## Supported Languages

| Language        | Adapter         | Binary needed        |
|-----------------|-----------------|----------------------|
| Python          | debugpy         | `python -m debugpy`  |
| JavaScript / TS | js-debug        | `js-debug-adapter`   |
| Go              | delve           | `dlv`                |
| C / C++         | codelldb        | `codelldb`           |
| Rust            | codelldb        | `codelldb`           |
| Swift           | codelldb        | `codelldb`           |
| C#              | netcoredbg      | `netcoredbg`         |
| Java            | java-debug      | `java-debug-adapter` |
| Kotlin          | kotlin-debug    | `kotlin-debug-adapter`|
| PHP             | php-debug       | `php-debug-adapter`  |
| Ruby            | rdbg            | `rdbg`               |
| Lua (Neovim)    | osv             | one-small-step-for-vimkind |

Adapter binaries are the user's responsibility to install (via mason, system
package manager, or manually). tiny-debugger configures, it doesn't install.

## Configuration (optional)

```lua
require("tiny-debugger").setup({
  help_on_enter = true,       -- show help box when entering debug mode
  builtin_adapters = true,    -- register built-in language adapters

  keys = {
    continue = "c",           -- override any key
    step_over = false,        -- set to false to disable
  },

  adapters = {
    zig = { ... },            -- add new language adapters
  },

  dapui = { ... },            -- override nvim-dap-ui layout
  virtual_text = { ... },     -- override virtual text settings
})
```

## Statusline

```lua
require("tiny-debugger").active()  -- returns true/false
```

## Help

```
:help tiny-debugger
```

## License

MIT
