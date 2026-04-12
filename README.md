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

`<leader>d` toggles debug mode. `<leader>x` sets breakpoints (works anytime).

During debug mode, single-key controls:

| Key | Action                 | Key | Action                 |
|-----|------------------------|-----|------------------------|
| `c` | Continue               | `W` | Watch expression       |
| `s` | Step over              | `K` | Hover / inspect        |
| `d` | Step into              | `E` | Eval in REPL           |
| `r` | Step out               | `q` | Terminate session      |
| `C` | Run to cursor          | `R` | Restart session        |
| `?` | Help popup             |     |                        |

Always available (no debug mode needed):

| Key | Action                 |
|-----|------------------------|
| `<leader>x` | Toggle breakpoint      |
| `<leader>X` | Conditional breakpoint |
| `<leader>D` | Clear all breakpoints  |

All navigation keys preserved. Modal keybindings vanish when you exit debug mode.

## Supported Languages

Adapter binaries must be installed (via mason, package manager, etc).

| Language        | Adapter    | Language     | Adapter            |
|-----------------|------------|--------------|--------------------|
| Python          | debugpy    | C#           | netcoredbg         |
| JavaScript / TS | js-debug   | Java         | java-debug-adapter |
| Go              | delve      | Kotlin       | kotlin-debug       |
| C / C++         | codelldb   | PHP          | php-debug          |
| Rust            | codelldb   | Ruby         | rdbg               |
| Swift           | codelldb   | Lua (Neovim) | osv                |

## License

MIT
