# tiny-debugger.nvim

A zero-config debugging experience for Neovim 0.12+. One plugin install, full
IDE-class debugging: inline variable values, hover inspection, persistent
breakpoints, watch expressions, and modal keybindings that just work.

## Install

```lua
vim.pack.add("swaits/tiny-debugger.nvim")
```

That's it. No other config needed. See `:help tiny-debugger` for customization.

## Usage

Everything lives under `<leader>d` (with which-key support if installed):

| Key | Action | Available |
|-----|--------|-----------|
| `<leader>dd` | Toggle debug mode | Always |
| `<leader>dx` | Toggle breakpoint | Always |
| `<leader>dX` | Conditional breakpoint | Always |
| `<leader>dD` | Clear all breakpoints | Always |

During debug mode, single-key controls:

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `c` | Continue | `x` | Toggle breakpoint |
| `s` | Step over | `X` | Conditional breakpoint |
| `d` | Step into | `D` | Clear all breakpoints |
| `r` | Step out | `W` | Watch expression |
| `C` | Run to cursor | `K` | Hover / inspect |
| `q` | Terminate session | `E` | Eval in REPL |
| `R` | Restart session | `?` | Help popup |

All navigation keys preserved. Modal keybindings vanish when you exit debug mode.

## Supported Languages

Adapter binaries must be installed (via mason, package manager, etc).

| Language | Adapter | Language | Adapter |
|----------|---------|----------|---------|
| Python | debugpy | C# | netcoredbg |
| JavaScript / TS | js-debug | Java | java-debug-adapter |
| Go | delve | Kotlin | kotlin-debug |
| C / C++ | codelldb | PHP | php-debug |
| Rust | codelldb | Ruby | rdbg |
| Swift | codelldb | Lua (Neovim) | osv |

## License

MIT
