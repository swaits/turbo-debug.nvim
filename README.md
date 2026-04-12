# turbo-debug.nvim

A zero-config debugging experience for Neovim 0.12+. One plugin install, full
IDE-class debugging: inline variable values, hover inspection, persistent
breakpoints, watch expressions, and modal keybindings that just work.

Inspired by Turbo Pascal — the first IDE where you could just hit a key
and start debugging.

![turbo-debug screenshot](https://github.com/user-attachments/assets/TODO)

## Install

```lua
vim.pack.add("swaits/turbo-debug")
```

That's it. No other config needed. See `:help turbo-debug` for customization.

## How It Works

turbo-debug is **modal**. Press `<leader>dd` and you enter debug mode — the
UI opens, keybindings activate, and you're debugging. Press `q` or
`<leader>dd` again and everything disappears. Your editor is exactly as it
was before.

This modal approach is inspired by
[debugmaster.nvim](https://github.com/MironPascalCaseFan/debugmaster.nvim).
During a debug session you need to **navigate** code and **inspect** state.
You do not need to **edit**. So debug mode shadows editing keys (`c`, `d`,
`s`, `r`, `x`) with debug actions and leaves all navigation keys untouched
(`h`, `j`, `k`, `l`, `w`, `b`, `e`, `f`, `/`, `n`, etc.).

When debug mode ends, every keybinding is restored to exactly what it was.

## Keybindings

Everything lives under `<leader>d` (with
[which-key](https://github.com/folke/which-key.nvim) support if installed):

| Key | Action |
|-----|--------|
| `<leader>dd` | Toggle debug mode |
| `<leader>dx` | Toggle breakpoint |
| `<leader>dX` | Conditional breakpoint |
| `<leader>dD` | Clear all breakpoints |

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

Press `?` during debug mode for a quick reference.

## Supported Languages

turbo-debug ships adapter configs for 12 languages. You install the adapter
binary (via [mason.nvim](https://github.com/williamboman/mason.nvim), your
package manager, or manually) — turbo-debug handles all the configuration.

| Language | Adapter | Language | Adapter |
|----------|---------|----------|---------|
| Python | debugpy | C# | netcoredbg |
| JavaScript / TS | js-debug | Java | java-debug-adapter |
| Go | delve | Kotlin | kotlin-debug |
| C / C++ | codelldb | PHP | php-debug |
| Rust | codelldb | Ruby | rdbg |
| Swift | codelldb | Lua (Neovim) | osv |

Rust gets special treatment: pressing `c` runs `cargo build` automatically
and picks the binary via `vim.ui.select`.

## What This Plugin Actually Does

turbo-debug is **glue**. It does not implement a debugger, a UI framework,
virtual text rendering, or breakpoint persistence. It configures and wires
together these excellent plugins into a single cohesive experience:

| Plugin | What it provides |
|--------|-----------------|
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | DAP client — the core debug engine |
| [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) | Scopes, stacks, watches, REPL, console UI |
| [nvim-nio](https://github.com/nvim-neotest/nvim-nio) | Async IO (required by nvim-dap-ui) |
| [nvim-dap-virtual-text](https://github.com/theHamsta/nvim-dap-virtual-text) | Inline variable values in source code |
| [persistent-breakpoints.nvim](https://github.com/Weissle/persistent-breakpoints.nvim) | Breakpoints that survive restarts |

All five are loaded automatically via `vim.pack.add`. You never declare them.

Adapter configurations are inlined from the work of these projects (no
runtime dependency, we just studied their configs and wrote plain Lua tables):

- [nvim-dap-python](https://github.com/mfussenegger/nvim-dap-python)
- [nvim-dap-go](https://github.com/leoluz/nvim-dap-go)
- [nvim-dap-vscode-js](https://github.com/mxsdev/nvim-dap-vscode-js)
- [nvim-dap-lldb](https://github.com/julianolf/nvim-dap-lldb)
- [nvim-dap-cs](https://github.com/NicholasMata/nvim-dap-cs)
- [nvim-dap-ruby](https://github.com/suketa/nvim-dap-ruby)
- [nvim-dap-kotlin](https://github.com/Mgenuit/nvim-dap-kotlin)

## License

MIT
