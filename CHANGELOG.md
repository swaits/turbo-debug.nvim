# Changelog

## 0.1.0 — 2026-04-11

Initial release.

### Features

- **Zero-config debugging** — one line install, everything works
- **Modal keybindings** — single-key debug controls (`c`/`s`/`d`/`r`/`q`), active only during debug mode, cleanly removed on exit
- **Persistent breakpoints** — survive Neovim restarts via persistent-breakpoints.nvim
- **Inline virtual text** — variable values shown in source code during stepping
- **Hover inspection** (`K`) and **watch expressions** (`W`) from the code window
- **REPL eval** (`E`) — floating REPL for expression evaluation
- **Help splash** — centered keybinding reference on debug mode entry (3s auto-dismiss), re-openable with `?`
- **Debug mode chrome** — winbar indicator, cursor highlight, dapui panel titles
- **dapui integration** — opinionated layout with controls toolbar, labeled panels (Scopes, Watches, Call Stack, Console, REPL)
- **which-key support** — `<leader>d` debug group registered automatically if which-key is installed
- **`quit_exits_mode`** option — control whether `q` terminates only or also exits debug mode

### Adapters (12 languages)

- **Python** — debugpy with virtualenv auto-detection (VIRTUAL_ENV, CONDA_PREFIX, .venv)
- **Rust** — codelldb with `cargo build` integration and `vim.ui.select` binary picker
- **Go** — delve with auto-launch (file and package configs)
- **C / C++ / Swift** — codelldb with executable prompt
- **JavaScript / TypeScript** — js-debug-adapter (pwa-node, launch + attach)
- **C#** — netcoredbg
- **Java** — java-debug-adapter
- **Kotlin** — kotlin-debug-adapter
- **PHP** — php-debug (Xdebug listener)
- **Ruby** — rdbg (launch + attach)
- **Lua (Neovim)** — osv (optional, graceful skip if not installed)

### Keybinding scheme

- `<leader>dd` — toggle debug mode
- `<leader>dx` / `<leader>dX` / `<leader>dD` — breakpoints (always available)
- `c s d r C x X D W K E q R ?` — modal keys (debug mode only)
