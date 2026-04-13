# Changelog

## 0.2.1 — 2026-04-12

Language coverage release. 10 new DAP adapters bring built-in support from
12 to 22 languages, prioritized by language popularity and DAP adapter
maturity.

### Added

- **Dart** (with optional **Flutter**) — auto-detects `flutter` on PATH and
  adds a "Launch Flutter app" configuration alongside the plain Dart file
  launch. Uses `dart debug_adapter` / `flutter debug_adapter`.
- **Bash / Sh** — `bash-debug-adapter` with automatic `bashdb_dir` probing
  from the mason package path.
- **R** — `vscDebugger` R-package integration. Preflights the package via
  `Rscript` and silently skips registration if it's missing.
- **Elixir** — `elixir-ls-debugger` with `mix_task` launch (default task
  `test`). Falls back to the mason package `debugger.sh` if the wrapper
  binary isn't on PATH.
- **Haskell** — `haskell-debug-adapter`.
- **OCaml** — `ocamlearlybird`.
- **Zig / Nim / Crystal** — routed through the existing `codelldb` adapter
  via filetype extension (no new adapter; just added filetypes to the
  existing codelldb configuration).
- **F#** — routed through the existing `netcoredbg` adapter (same
  `.dll`-launch flow as C#).

### Internal

- Extended `tests/test_adapters.lua` to cover the three new modular adapter
  modules (`dart`, `bash`, `r`).
- All new registrations follow the existing `find_executable` +
  `loader.register` pattern and silently skip when the required binary
  isn't found — matches the "no noise when prereqs missing" invariant of
  the previously-shipped adapters.

## 0.2.0 — 2026-04-12

Major UI rework and stability release. Two floating chrome bars replace the
old single toolbar, every resize/tabline-toggle edge case is handled, and
every highlight now derives from the user's colorscheme.

### Breaking changes

- **`quit_exits_mode` option removed.** `q` is now context-aware: if a DAP
  session is running, `q` terminates the session but keeps debug mode
  active (so you can read the Console / inspect post-mortem state). Press
  `q` again to exit debug mode.
- **`help_on_enter` default is now `false`** (was `true`). The control bar
  always shows `(?) help`, so the auto-popup is no longer needed. Set to
  `true` to restore the splash behavior.
- **Default layout changed.** Sidebar panes are now Call Stack → Scopes →
  Watches → Breakpoints (all 25%). REPL is no longer in the default
  layout — press `E` during debug mode to open it as a floating window.
- **Console pane sizing.** Bottom Console pane is `max(8 rows, 20% of
  editor lines)` (previously hardcoded). Configurable via `console_height`.

### Added

- **Two-bar floating chrome**, independent of any statusline plugin:
  - Status bar (top, 2 rows): brand, live `dap.status()` text, state chip
    (` DEBUG · READY ` / ` · RUNNING ` / ` · PAUSED `)
  - Control bar (bottom, 2 rows, above statusline): clickable buttons for
    continue, step over, step into, step out, restart (during session),
    terminate; `(?) help` right-anchored
  - Italic qualifiers (`over`, `into`, `out`) on step controls — dropped
    automatically at narrow widths
- **Keymap-aware control bar**: legend reflects the user's actual
  remapped keys (honors `keys` override; disabled actions are omitted)
- **IP arrow markers** on stopped lines: paired 👉 gutter sign (priority
  500 so it always wins over breakpoint signs) + 👈 REASON virtual text
  at EOL
- **Optional debug-mode colorscheme** via `colorscheme` option — theme
  swaps on debug enter, restores on exit
- **Theme-agnostic separator color**: derives from `WinBar.fg` so the bar
  chrome matches any colorscheme; global `WinSeparator` override during
  debug mode gives the whole UI a consistent edge color
- **`clear_console_on_start`** (default `true`): wipe Console scrollback
  on session start/restart while preserving the terminal channel
- **`collapsed_scopes`** (default `{ "Registers" }`): auto-collapse noisy
  scopes; codelldb doesn't mark Registers expensive even though it's a
  huge dump
- **`max_value_width`** (default `2000`): per-line truncation for values
  in Scopes/Watches; prevents register-dump bleed
- **`console_refresh_ms`** (default `50`): trailing-edge throttle for
  Console repaints under high-throughput stdout
- **`sidebar`** option — `"left"` (default) or `"right"`
- **`active_window_highlight`** (default `true`): dim inactive dapui pane
  borders so the focused pane is visually obvious
- **`W` and `K` in visual mode**: watch / hover operate on the selection
- Live `dap.status()` polling via `User DapProgressUpdate` autocmd —
  status text stays current across progress messages
- Source window is focused before DAP jumps on `event_stopped`, so
  stepped-into library files open in the source area (not in a bar or
  dapui pane)
- Console repaint throttle prevents editor lag under chatty programs

### Changed

- Bars are now real splits (not overlapping floats) — dapui and source
  windows tuck between them naturally
- `pin_dapui_sizes()` only re-pins on EXTERNAL geometry changes
  (bufferline tabline toggle, `wincmd =`) detected by total-height
  delta; user's manual pane drags survive
- `ensure_dapui()` runs ONCE per plugin lifetime (not per `M.enter`),
  avoiding "Debug adapter didn't respond" timeouts on toggle
- Bars clamp to exactly 2 rows on every VimResized / WinResized (prevents
  stray EOB `~` when nvim grows a fixed-height window)
- `setup()` is now fully idempotent — safe to call multiple times with
  different opts, and `plugin/turbo-debug.lua`'s deferred auto-setup
  yields to explicit user `setup({...})`
- Copyright holder updated to `Stephen Waits <steve@waits.net>`

### Fixed

- Bars recreate themselves if killed by shrink-below-minimum resize or
  tabline appearance/disappearance
- Inherited `winbar` from the splitting source window is cleared on bar
  windows (was showing phantom separator rows)
- Layout re-asserts correctly after `wincmd =` (tiny-equalizer pass)
- Sidebar proportions stable across re-entry (no drift across toggles)
- Bar separators bright on both outward edges (top-of-sbar, bottom-of-cbar)
- Deferred dependency loading: `plugin/turbo-debug.lua` waits for
  `vim.pack.add` to finalize runtimepath before calling `setup()`

### Internal

- Extracted 10+ helper functions in `mode.lua` (`win_ok`, `buf_ok`,
  `is_dapui_pane_ft`, `for_each_dapui_pane`, `safe_extmark`,
  `bar_set_lines`, `safe_set_height`, `if_still_active`,
  `invalidate_dead_bars`, `focus_source_win`, `unset_and_restore`,
  `install_cs_listener`) — deduped ~25 call sites
- Data-driven sign definitions (`breakpoints.lua`) and Python
  interpreter candidate probing
- Dead code removed: unused `reposition_bars` stub, vestigial
  `sbar_zones` / `handle_sbar_click` click infrastructure (status bar
  has no clickable zones)
- Added regression tests: `test_render_bars` (sbar/cbar output,
  dimensions, zones, overflow fallback), `test_highlights_cs`
  (ColorScheme augroups, highlight re-apply), `test_helpers`
  (keyof branching, source_window filtering)
- `stylua.toml` added; all Lua code formatted

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
