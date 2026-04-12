# turbo-debug.nvim — Product Specification

## What Is This?

A Neovim 0.12+ plugin that gives you a fully-featured, beautiful debugging
experience out of one line of config. The kind of debugger you remember from
Turbo Pascal, Delphi, Visual Studio — where you just hit a key and everything
works: breakpoints persist, variables show their values inline, you can hover
anything, watch expressions update live, and the whole UI is laid out like
someone cared.

Under the hood it wires together nvim-dap, nvim-dap-ui, nvim-dap-virtual-text,
and persistent-breakpoints into a single cohesive experience with modal
keybindings. The user installs one plugin and gets everything.

```lua
vim.pack.add("swaits/turbo-debug.nvim")
```

That's it. That's the whole setup.

## Design Principles

1. **Just works.** Install it, press `<leader>d`, start debugging. No adapter
   config needed for common languages. No DAP boilerplate. No reading wiki
   pages to get "hello world" to hit a breakpoint.

2. **A real debugger.** Inline variable values in the source code. Hover any
   expression to see its value. Persistent breakpoints that survive restarts.
   Watch expressions you can add from the code window. Scopes, stacks, REPL,
   console — all laid out cleanly. This is not a toy.

3. **Minimal code, maximal experience.** We don't reimplement anything. We
   configure nvim-dap, nvim-dap-ui, nvim-dap-virtual-text, and
   persistent-breakpoints with opinionated defaults and glue them together
   with modal keybindings. The smallest amount of code that delivers a
   professional debugging experience.

4. **Principle of least surprise.** Keybindings should be guessable. `c` is
   continue. `s` is step. `q` is quit. If you can't guess it, the help box is
   right there. No cleverness that requires documentation.

5. **Modal, not polluting.** Debug keybindings exist only during a debug
   session. They shadow editing keys you don't need while debugging. They
   never shadow navigation keys you do need. When the session ends, your
   editor is exactly as it was.

6. **Configurable, not opinionated to a fault.** Every keybinding is
   overridable. The dap-ui layout can be replaced. Adapter configs can be
   extended. But the defaults should be good enough that most people never
   touch any of it.

7. **Clean, simple code everywhere.** No abstraction for abstraction's sake.
   No metaprogramming tricks. A new contributor should read the source top to
   bottom in ten minutes and understand everything.

## What The User Gets

One plugin install. Zero configuration. All of this:

- **Inline virtual text** showing variable values right in the source code,
  updated live as you step. (via nvim-dap-virtual-text)
- **Hover inspection** — press `K` on any expression to see its value in a
  floating window. Works on complex expressions, not just single variables.
- **Persistent breakpoints** — breakpoints survive Neovim restarts. They're
  part of your project, not your session. Visible in the sign column at all
  times. (via persistent-breakpoints.nvim)
- **Watch expressions** — press `W` on any variable in your code and it gets
  added to the watches panel. No focus switch, no prompt.
- **Scopes panel** — all local/global variables in the current frame,
  expandable, updated live.
- **Stack traces** — navigate the call stack, jump to any frame.
- **REPL** — evaluate arbitrary expressions in the debug context.
- **Console** — program stdout/stderr.
- **Conditional breakpoints** — `X` to set a breakpoint with a condition.
- **Modal keybindings** — single-key controls for all debug actions, active
  only during debug sessions.
- **Help box** — shows all keybindings on debug mode entry, re-openable with
  `?` at any time.
- **Zero-config adapters** for the world's top languages.

## Dependencies (Managed Automatically)

The user never sees or declares these. turbo-debug calls `vim.pack.add` for
each one internally:

| Dependency                        | What it provides                          |
|-----------------------------------|-------------------------------------------|
| `mfussenegger/nvim-dap`           | DAP client — the core debug engine        |
| `rcarriga/nvim-dap-ui`            | Scopes, stacks, watches, REPL, console UI |
| `nvim-neotest/nvim-nio`           | Async IO (required by nvim-dap-ui)        |
| `theHamsta/nvim-dap-virtual-text` | Inline variable values in source code     |
| `Weissle/persistent-breakpoints.nvim` | Breakpoints that survive restarts     |

Everything loads eagerly at startup. No lazy loading. Startup cost is
negligible.

### Why These Five and Nothing Else

We evaluated every plugin in the nvim-dap ecosystem. The rule: if we can
replicate what a plugin does in <50 lines of our own code, we don't add the
dependency. If the plugin does something non-trivial that would take hundreds
of lines and deep domain knowledge to replicate, we depend on it.

**nvim-dap-virtual-text** — KEEP. Uses treesitter to find variable definition
sites, handles scope-aware display, changed-value highlighting, comment-style
formatting. 400+ lines of treesitter integration we'd have to replicate. Not
worth it.

**persistent-breakpoints.nvim** — KEEP. File-based breakpoint persistence with
sign management. Solves a real problem cleanly.

**nvim-dap-python, nvim-dap-go, nvim-dap-ruby, nvim-dap-lldb, nvim-dap-kotlin,
nvim-dap-cs, nvim-dap-vscode-js** — DO NOT DEPEND. Each is just an adapter
table + config table + maybe 20 lines of environment detection. We steal the
configs and inline them as plain Lua tables in our `configs/` directory. No
plugin needed.

**mason-nvim-dap** — DO NOT DEPEND. Our principle is "we configure, the user
installs binaries." We just look for adapters on PATH or in standard mason
install paths as a fallback.

**dap-buddy** — DO NOT DEPEND. Abandoned since 2022. Dead project.

**nvim-dap-rr** — DO NOT DEPEND. Reverse debugging is niche (Linux-only,
C/C++/Rust only). Out of scope.

**dap-utils** — DO NOT DEPEND. Grab bag of features we either already have
(breakpoint persistence) or don't want (telescope integration).

## Installation

```lua
-- init.lua
vim.pack.add("swaits/turbo-debug.nvim")
```

One line. One plugin. Everything works.

### Configuration (optional)

```lua
require("turbo-debug").setup({
  -- all fields optional, these are the defaults
  help_on_enter = true,     -- show help box when entering debug mode
  keys = { ... },           -- override any keybinding
  adapters = { ... },       -- override or add language adapters
  dapui = { ... },          -- override nvim-dap-ui layout/settings
  virtual_text = { ... },   -- override nvim-dap-virtual-text settings
})
```

## Debug Mode

`<leader>d` toggles debug mode. Entering debug mode:

1. Opens nvim-dap-ui with the configured layout.
2. Enables nvim-dap-virtual-text (inline variable values appear in source).
3. Activates modal keybindings (buffer-local, vanish on exit).
4. Changes the cursor highlight to indicate you're in debug mode.
5. Shows the help box (bottom-right float, auto-closes on first keypress).
   Disable with `help_on_enter = false`.
6. If no DAP session is active, waits for `c` (continue) to launch one.

Exiting debug mode (any of):

- `<leader>d` again (manual toggle)
- `q` (terminate session — auto-exits debug mode)
- DAP session ends naturally (program exits, etc.)

On exit: all modal keybindings removed, nvim-dap-ui closed, virtual text
cleared, cursor highlight restored. The editor is exactly as it was before.

## Keybindings

### Philosophy

During debugging you need to **navigate code** (read, jump around, search) and
you need to **interact with the REPL/terminal** (insert mode). You do not need
to **edit** code. Therefore we shadow editing operators and leave all motions
and insert intact.

Left hand = flow control. Right hand = inspection. `?` = help.

### Default Map

| Key | Action                 | Mnemonic / Rationale                          |
|-----|------------------------|-----------------------------------------------|
| `c` | Continue               | Universal across all debuggers                |
| `s` | Step over              | **S**tep                                      |
| `d` | Step into              | **D**escend into the function                 |
| `r` | Step out               | **R**eturn from the function                  |
| `C` | Run to cursor          | **C**ontinue to cursor — extends `c`          |
| `x` | Toggle breakpoint      | X marks the spot (persistent)                 |
| `X` | Conditional breakpoint | Shift variant of `x` (also persistent)        |
| `W` | Watch expr under cursor| **W**atch (uses `<cexpr>` or visual selection) |
| `K` | Hover / inspect        | Matches vim LSP hover convention              |
| `E` | Eval in REPL           | **E**valuate                                  |
| `q` | Terminate session      | **Q**uit debugging                            |
| `R` | Restart session        | **R**erun                                     |
| `?` | Help popup             | Universal "show me what I can do"             |

### What's Sacrificed (and Why It's Fine)

| Key | Normal function     | Why it's safe to shadow                       |
|-----|---------------------|-----------------------------------------------|
| `c` | Change operator     | Not editing during debug                      |
| `s` | Substitute char     | Not editing; flash/leap: modal, so no conflict|
| `d` | Delete operator     | Not editing during debug                      |
| `r` | Replace char        | Not editing during debug                      |
| `x` | Delete char         | Not editing during debug                      |
| `q` | Record macro        | Not recording macros during debug             |
| `C` | Change to EOL       | Not editing during debug                      |
| `X` | Backspace           | Not editing during debug                      |
| `R` | Replace mode        | Nobody enters replace mode during debug       |
| `W` | WORD forward        | Minor loss; `w` (word forward) still works    |
| `E` | End of WORD         | Minor loss; `e` (end of word) still works     |
| `?` | Reverse search      | Minor loss; `/` still works for forward search|

### What's Preserved

All navigation: `h j k l w b e f F t T / n N 0 ^ $ G g { } % [ ]`

Insert mode access: `i a o O` (needed for REPL, terminal, editing watches)

Visual, yank, put: `v V y p u` (useful for copying values, inspecting ranges)

All Ctrl/leader combos: untouched.

### Configuration

```lua
keys = {
  continue        = "c",
  step_over       = "s",
  step_into       = "d",
  step_out        = "r",
  run_to_cursor   = "C",
  breakpoint      = "x",
  cond_breakpoint = "X",
  watch           = "W",
  hover           = "K",
  eval            = "E",
  terminate       = "q",
  restart         = "R",
  help            = "?",
}
```

Override any key. Set a key to `false` to disable it.

## Persistent Breakpoints

Breakpoints are managed by persistent-breakpoints.nvim, not raw nvim-dap. This
means:

- Breakpoints survive across Neovim restarts.
- `x` calls `require("persistent-breakpoints.api").toggle_breakpoint()`.
- `X` calls the conditional breakpoint equivalent.
- Breakpoint signs are visible at all times, not just during debug sessions.

Note: `x` and `X` work at all times — they are the few keybindings active
both inside and outside debug mode. Setting breakpoints should never require
entering a special mode first.

## The Debugging Experience

### Inline Virtual Text

When a debug session is active, variable values appear as virtual text inline
in the source code, right next to where they're used. This updates live as you
step. No need to hover or check the scopes panel for simple values — they're
just there in your code.

Powered by nvim-dap-virtual-text with sensible defaults (commented style so
it doesn't look like real code, changed values highlighted, current frame
only).

### Hover

`K` on any expression opens a floating window showing its current value.
Works in normal mode (uses word under cursor) and visual mode (uses
selection). Follows the same `K` convention as LSP hover.

### Watch

`W` grabs `<cexpr>` under the cursor (or the visual selection) and adds it
to the watches panel in nvim-dap-ui. No focus switch, no prompt, no typing.
The watch updates live as you step through code.

To remove or edit watches, navigate to the watches panel in the sidebar and
use the standard nvim-dap-ui element keybindings.

## UI Layout

turbo-debug configures nvim-dap-ui with a clean, purposeful layout:

```
┌──────────────────────────────────┬──────────────────┐
│                                  │ Scopes     (50%) │
│                                  │  > local         │
│          Source Code              │    x = 42        │
│                                  │    name = "hi"   │
│     x = 42  -- « virtual text    │                  │
│     name = "hello"               ├──────────────────┤
│ >>  result = compute(x)          │ Watches    (25%) │
│     return result                │   compute(x): 84 │
│                                  ├──────────────────┤
│                                  │ Stacks     (25%) │
│                                  │   main:12        │
│                                  │ > compute:7      │
├──────────────────────────────────┴──────────────────┤
│ REPL (50%)               │ Console (50%)            │
│ > print(x)               │ [stdout] Starting...     │
│ 42                       │ [stdout] Processing...   │
└──────────────────────────┴──────────────────────────┘
```

### Layout Rationale

**Left sidebar (40 columns):**
- Scopes gets 50% — this is what you look at 80% of the time.
- Watches gets 25% — right below scopes, so `W` results appear in your
  peripheral vision immediately.
- Stacks gets 25% — you glance at it, you don't study it.

**Bottom tray (12 lines):**
- REPL and Console share the space. REPL is interactive (you type
  expressions), Console shows program output.

**What's excluded from the layout:**
- Breakpoints panel — persistent-breakpoints shows signs in the gutter.
- Controls toolbar — our modal keys replace it.

**Overridable:** Pass `opts.dapui` to replace the entire layout.

## Preconfigured Adapters

The plugin ships working DAP adapter + configuration for the world's top
languages. No language-specific plugins are added as dependencies — we inline
the configs as plain Lua tables, stealing the good parts from existing plugins
and the nvim-dap wiki.

### Adapter Table

| Language        | Adapter         | Config source                     | Our code         |
|-----------------|-----------------|-----------------------------------|------------------|
| Python          | debugpy         | nvim-dap-python (mfussenegger)    | ~30 lines        |
| JavaScript / TS | js-debug        | nvim-dap-vscode-js (mxsdev)       | ~25 lines        |
| Go              | delve           | nvim-dap-go (leoluz)              | ~20 lines        |
| C / C++         | codelldb        | nvim-dap-lldb (julianolf) + wiki  | ~20 lines        |
| Rust            | codelldb        | Same as C/C++, shared config      | ~5 lines (alias) |
| C#              | netcoredbg      | nvim-dap-cs (NicholasMata) + wiki | ~15 lines        |
| Java            | java-debug      | nvim-jdtls patterns + wiki        | ~20 lines        |
| PHP             | php-debug       | nvim-dap wiki + community configs | ~15 lines        |
| Ruby            | rdbg            | nvim-dap-ruby (suketa)            | ~20 lines        |
| Kotlin          | kotlin-debug    | nvim-dap-kotlin (Mgenuit)         | ~15 lines        |
| Swift           | codelldb        | Same as C/C++, shared config      | ~5 lines (alias) |
| Lua (Neovim)    | osv             | one-small-step-for-vimkind + wiki | ~15 lines        |

### What We Steal From Each Source

**nvim-dap-python (~200 LOC plugin → ~30 lines for us):**
- Adapter definition (executable type, `python -m debugpy.adapter`)
- Virtualenv auto-detection: checks `VIRTUAL_ENV`, `CONDA_PREFIX`, then
  probes for `.venv`/`venv`/`env`/`.env` relative to cwd and LSP root
- Launch config for current file
- We skip: test runner integration (test_method, test_class) — out of scope

**nvim-dap-go (~300 LOC plugin → ~20 lines for us):**
- Adapter definition (server type, auto-launches dlv on random port)
- Launch config for current file and package
- We skip: individual test debugging — out of scope

**nvim-dap-vscode-js (~400 LOC plugin → ~25 lines for us):**
- Adapter definition for `pwa-node` (uses `js-debug-adapter` binary)
- Launch configs for file, attach, and node process
- Shared across `javascript`, `typescript`, `javascriptreact`,
  `typescriptreact` filetypes
- We skip: Chrome/Edge/extension host adapters — uncommon for most users

**nvim-dap-lldb / codelldb wiki (~150 LOC → ~20 lines for us):**
- Adapter definition (server type, TCP, codelldb binary)
- Mason path fallback (`~/.local/share/nvim/mason/bin/codelldb`)
- Launch config with program picker (`vim.fn.input`)
- Shared across `c`, `cpp`, `rust`, `swift` filetypes

**nvim-dap-cs (~100 LOC → ~15 lines for us):**
- Adapter definition (executable type, `netcoredbg --interpreter=vscode`)
- Launch config for .NET DLL with path picker
- Mason path fallback

**nvim-dap-ruby (~100 LOC → ~20 lines for us):**
- Adapter definition (server type, `rdbg` with DAP mode)
- Launch config for current file and attach config
- Rails server launch config (rdbg + `bin/rails s`)

**nvim-dap-kotlin (~150 LOC → ~15 lines for us):**
- Adapter definition (executable type, `kotlin-debug-adapter`)
- Launch config for main function
- We skip: test debugging — out of scope

**PHP (wiki + community → ~15 lines for us):**
- Adapter definition (executable type, node + `phpDebug.js`)
- Mason path fallback for php-debug-adapter
- Launch config to listen for Xdebug on port 9003

**Java (nvim-jdtls patterns → ~20 lines for us):**
- Adapter definition (executable type, java-debug-adapter)
- Launch config for current class
- Note: Java debugging is tightly coupled to nvim-jdtls for full
  functionality. Our config provides the basics; users with complex Java
  setups will likely use nvim-jdtls directly.

**Lua/Neovim (wiki → ~15 lines for us):**
- Adapter definition via one-small-step-for-vimkind (osv)
- Launch config for current Neovim instance debugging
- Optional dependency — only activated if osv is installed

### Adapter Path Resolution

For every adapter, we check paths in this order:
1. User override via `opts.adapters`
2. Binary on `$PATH`
3. Standard mason install path (`~/.local/share/nvim/mason/bin/`)
4. Common system paths (`/usr/bin/`, `/usr/local/bin/`)

### Behavior

- On first `c` (continue), if no `dap.configurations` exist for the current
  filetype, turbo-debug installs its built-in config automatically.
- If the user has already configured adapters for a filetype via nvim-dap
  directly, turbo-debug does not override them.
- Adapter binary installation is the user's responsibility (mason, system
  package manager, or manual). turbo-debug configures, it doesn't install.

### Configuration

```lua
require("turbo-debug").setup({
  adapters = {
    python = { ... },      -- override built-in
    zig = { ... },          -- add new language
  },
  builtin_adapters = false,  -- disable all built-ins
})
```

## Help Box

The help box is a small floating window (bottom-right corner) that lists all
active keybindings. It appears automatically when entering debug mode
(configurable via `help_on_enter`). It auto-closes on the first keypress so
it never blocks workflow.

`?` re-opens it at any time during debug mode.

Content is generated dynamically from the active keymap table, so it always
reflects the user's configuration.

## Mode Lifecycle

```
NORMAL MODE
    │
    ├── x / X work here too (persistent breakpoints, always available)
    │
    ├── <leader>d ──► DEBUG MODE
    │                    │
    │                    ├── Modal keybindings active
    │                    ├── nvim-dap-ui open (scopes, watches, stacks, repl, console)
    │                    ├── Virtual text enabled (inline variable values)
    │                    ├── Cursor highlight changed
    │                    ├── Help box shown (if help_on_enter)
    │                    │
    │                    ├── c ──► Launches/continues DAP session
    │                    ├── s/d/r ──► Step over/into/out
    │                    ├── K ──► Hover inspect value under cursor
    │                    ├── W ──► Add watch for expr under cursor
    │                    ├── E ──► Eval expression in REPL
    │                    ├── q ──► Terminates session ──► exits debug mode
    │                    ├── <leader>d ──► exits debug mode (session stays if active)
    │                    │
    │                    └── Session ends naturally ──► exits debug mode
    │
    ◄── Editor restored (keymaps, UI, virtual text, cursor)
```

## Implementation Notes

### Scope

Clean, readable Lua. A `plugin/` entry point, a core module, and a `configs/`
directory for per-language adapter definitions (plain tables, no logic). Every
file should be short enough to read in one sitting.

### File Structure

This is a canonical Neovim plugin with proper help docs, license, and
everything a user or contributor expects.

```
turbo-debug.nvim/
├── LICENSE                     -- MIT
├── README.md                   -- install, quick start, screenshots
├── CONTRIBUTING.md             -- how to add adapters, run tests
├── doc/
│   └── turbo-debug.txt       -- :help turbo-debug (vimdoc format)
├── plugin/
│   └── turbo-debug.lua       -- vim.pack.add deps, global x/X maps, setup
├── lua/
│   └── turbo-debug/
│       ├── init.lua            -- public API (setup, toggle, active)
│       ├── config.lua          -- default opts, deep merge with user opts
│       ├── mode.lua            -- enter/exit debug mode, keybinding mgmt
│       ├── help.lua            -- help box float
│       ├── ui.lua              -- dap-ui layout config and wiring
│       ├── virtual_text.lua    -- nvim-dap-virtual-text config and wiring
│       ├── breakpoints.lua     -- persistent-breakpoints config and wiring
│       └── adapters/
│           ├── init.lua        -- adapter loader, path resolution, register
│           ├── python.lua      -- adapter + config + venv detection
│           ├── javascript.lua  -- js/ts/jsx/tsx adapter + configs
│           ├── go.lua          -- delve adapter + configs
│           ├── c.lua           -- codelldb adapter (c/cpp/rust/swift)
│           ├── cs.lua          -- netcoredbg adapter
│           ├── java.lua        -- java-debug adapter
│           ├── php.lua         -- php-debug adapter
│           ├── ruby.lua        -- rdbg adapter
│           ├── kotlin.lua      -- kotlin-debug adapter
│           └── lua.lua         -- osv adapter (optional)
└── tests/
    ├── minimal_init.lua        -- minimal Neovim config for test harness
    ├── test_mode.lua           -- debug mode enter/exit tests
    ├── test_keys.lua           -- keybinding activation/restoration tests
    ├── test_help.lua           -- help box open/close/content tests
    ├── test_config.lua         -- opts merging, key override, key disable
    ├── test_adapters.lua       -- adapter path resolution, registration
    └── test_breakpoints.lua    -- persistent breakpoint integration tests
```

### Key Mechanisms

**Dependency management:** `plugin/turbo-debug.lua` calls `vim.pack.add`
for each of the five dependencies. The user never sees or manages them.

**Plugin wiring:** turbo-debug calls `setup()` on nvim-dap-ui,
nvim-dap-virtual-text, and persistent-breakpoints with its opinionated
defaults, deep-merged with any user overrides from `opts`.

**Modal keybindings:** Use `vim.keymap.set` with `buffer = 0` on enter,
delete them on exit. Stash any conflicting user mappings and restore them.

**Always-on breakpoints:** `x` and `X` are mapped globally (not just in
debug mode) and delegate to persistent-breakpoints.nvim API.

**Watch from code:** `W` grabs `vim.fn.expand("<cexpr>")` in normal mode or
the visual selection, then programmatically inserts it into the watches
element buffer.

**Auto-exit:** Hook into `dap.listeners.after.event_terminated` and
`dap.listeners.after.event_exited` to leave debug mode when session ends.

**Cursor highlight:** Set `dCursor` highlight group on enter, clear on exit.

**Help box:** `vim.api.nvim_open_win` with scratch buffer, bottom-right.
Autocmd to close on any keypress. Content built from the keys table.

### What We Don't Do

- No custom UI widgets. nvim-dap-ui handles that.
- No statusline integration beyond exposing `require("turbo-debug").active()`.
- No telescope/fzf integration. Out of scope.
- No reverse debugging built-in. Users can remap keys.
- No test runner integration (debug nearest test). Out of scope.
- No project-specific launch.json parsing. nvim-dap supports this natively.
- No lazy loading. Everything loads. Startup cost is negligible.
- No adapter binary installation. We configure, the user installs.
- No language-specific plugin dependencies. We inline all adapter configs.

## Success Criteria

A user who has never configured DAP should be able to:

1. Add one line to their init.lua: `vim.pack.add("swaits/turbo-debug.nvim")`
2. Open a file in any of the world's top 10 languages.
3. Press `x` on a line to set a breakpoint (visible immediately in gutter).
4. Press `<leader>d` to enter debug mode. See the help box. See the UI.
5. Press `c` to start debugging. See the program stop at the breakpoint.
6. See variable values inline in the source code as virtual text.
7. Press `K` to hover a variable and see its full value.
8. Press `W` to add a watch expression.
9. Press `s` to step, see everything update live.
10. Press `q` to quit. Everything disappears. Editor is clean.
11. Close Neovim, reopen, see the breakpoint still there.

**Language coverage target:** Works out of the box (assuming the adapter binary
is installed) for: Python, JavaScript/TypeScript, Java/Kotlin, C/C++, C#, Go,
Rust, PHP, Ruby, Swift. And Lua for the Neovim plugin developers.

**The experience target:** This should feel like Visual Studio or IntelliJ,
not like a terminal debugger. Inline values, hover tooltips, persistent state,
clean layout — the full experience, in your terminal, from one line of config.

Total time from install to first breakpoint: under 2 minutes.
Total lines of user config: 1.
Total plugin dependencies the user manages: 0.
Total language-specific plugin dependencies: 0.

---

## Development Task Breakdown

Each task below is a single `jj commit`. Tasks are ordered so that each
builds on the last and the plugin is functional (if incomplete) at every
commit. Every task includes acceptance criteria and how to test it.

All source control uses **jj** (Jujutsu), never git.

---

### Task 1: Scaffold — canonical plugin structure

**What:** Create the repo with all directories, empty files, LICENSE (MIT),
empty README.md, CONTRIBUTING.md stub, and `doc/turbo-debug.txt` with
the vimdoc header and a skeleton table of contents.

**Files:**
```
LICENSE
README.md
CONTRIBUTING.md
doc/turbo-debug.txt
plugin/turbo-debug.lua          (empty, just a header comment)
lua/turbo-debug/init.lua        (returns empty table)
lua/turbo-debug/config.lua      (returns default opts table)
tests/minimal_init.lua            (minimal nvim init for testing)
```

**Acceptance criteria:**
- `nvim --clean -u tests/minimal_init.lua` starts without errors
- `:help turbo-debug` opens the help file (even if sparse)
- `:lua print(type(require("turbo-debug")))` prints `table`
- `jj log` shows exactly one clean commit

**Test:** Manual smoke test in Neovim.

**jj commit:** `scaffold: canonical plugin structure with docs and license`

---

### Task 2: Dependency management via vim.pack

**What:** `plugin/turbo-debug.lua` calls `vim.pack.add` for all five
dependencies. Validates Neovim >= 0.12. Prints a clear error and returns
if version check fails.

**Files:**
```
plugin/turbo-debug.lua
```

**Acceptance criteria:**
- On Neovim 0.12+: all five dependencies are downloaded and loadable
  (`require("dap")`, `require("dapui")`, etc. all succeed)
- On Neovim < 0.12: clear error message, no crash
- Dependencies do not appear in the user's plugin manager

**Test:** `nvim --clean -u tests/minimal_init.lua -c 'lua require("dap")'`
should not error. Test version gate by temporarily faking `vim.version()`.

**jj commit:** `deps: manage all dependencies via vim.pack`

---

### Task 3: Config module — defaults and deep merge

**What:** `lua/turbo-debug/config.lua` defines the full default options
table (keys, help_on_enter, dapui layout, virtual_text settings, etc.)
and exports a `merge(user_opts)` function that deep-merges user overrides.

**Files:**
```
lua/turbo-debug/config.lua
tests/test_config.lua
```

**Acceptance criteria:**
- `require("turbo-debug.config").defaults` returns the full table
- Merging `{ keys = { continue = "g" } }` overrides only that key
- Merging `{ keys = { continue = false } }` disables that key
- Merging `{}` returns defaults unchanged
- All other default values survive a partial override

**Test:** Automated. `tests/test_config.lua` runs assertions on merge
outputs. Run with `nvim --headless -u tests/minimal_init.lua -c 'luafile tests/test_config.lua'`.

**jj commit:** `config: default options table with deep merge`

---

### Task 4: Debug mode — enter, exit, keybinding lifecycle

**What:** `lua/turbo-debug/mode.lua` implements enter/exit debug mode.
On enter: sets buffer-local keymaps (stashing conflicts), sets `dCursor`
highlight. On exit: removes keymaps (restoring originals), clears highlight.
`lua/turbo-debug/init.lua` exposes `toggle()` and `active()`.

`plugin/turbo-debug.lua` maps `<leader>d` to `toggle()`.

**Files:**
```
lua/turbo-debug/init.lua
lua/turbo-debug/mode.lua
tests/test_mode.lua
tests/test_keys.lua
```

**Acceptance criteria:**
- `<leader>d` enters debug mode; all configured keys are active
- `<leader>d` again exits; all keys are removed
- A pre-existing user mapping for `c` is stashed on enter and restored on
  exit (verified by checking `vim.fn.maparg`)
- `require("turbo-debug").active()` returns `true`/`false` correctly
- Navigation keys (`h`, `j`, `w`, `b`, `/`, `n`, etc.) still work in
  debug mode
- `dCursor` highlight group is set on enter, cleared on exit

**Test:** Automated. `tests/test_mode.lua` enters mode, checks keymaps
exist via `vim.fn.maparg`, exits mode, checks keymaps removed and originals
restored. `tests/test_keys.lua` sets a custom mapping for `c`, enters
debug mode, verifies it's overridden, exits, verifies it's restored.

**jj commit:** `mode: enter/exit debug mode with keybinding lifecycle`

---

### Task 5: Help box

**What:** `lua/turbo-debug/help.lua` implements the floating help window.
Reads from the active keys config to build content dynamically. Opens
anchored to bottom-right. Closes on any keypress via autocmd.

**Files:**
```
lua/turbo-debug/help.lua
tests/test_help.lua
```

**Acceptance criteria:**
- `?` in debug mode opens a floating window listing all keybindings
- The window closes on the next keypress (any key)
- Content reflects the user's config (if `continue` is remapped to `g`,
  the help box shows `g` not `c`)
- If `help_on_enter = true`, the box opens automatically on mode enter
- If `help_on_enter = false`, it does not
- The window is non-focusable and non-intrusive (doesn't steal cursor)

**Test:** Automated. `tests/test_help.lua` opens help, checks
`vim.api.nvim_win_is_valid`, feeds a keypress, verifies window closed.
Tests with a remapped key to verify dynamic content.

**jj commit:** `help: floating help box with dynamic keybinding content`

---

### Task 6: UI wiring — nvim-dap-ui layout

**What:** `lua/turbo-debug/ui.lua` calls `dapui.setup()` with our
opinionated layout. Wires dap listeners to open/close UI on session
start/end. Integrates with mode enter/exit.

**Files:**
```
lua/turbo-debug/ui.lua
```

**Acceptance criteria:**
- Entering debug mode opens nvim-dap-ui with the configured layout
  (scopes 50%, watches 25%, stacks 25% left; repl + console bottom)
- Controls toolbar is disabled
- Exiting debug mode closes nvim-dap-ui
- DAP session ending naturally closes UI and exits debug mode
- User can override layout via `opts.dapui`

**Test:** Manual. Open a Python file with debugpy installed, enter debug
mode, verify layout matches the spec diagram. Exit, verify clean. Override
layout in opts, verify override takes effect.

**jj commit:** `ui: opinionated nvim-dap-ui layout with auto open/close`

---

### Task 7: Virtual text wiring

**What:** `lua/turbo-debug/virtual_text.lua` calls
`require("nvim-dap-virtual-text").setup()` with our defaults (commented
style, highlight changed variables, current frame only). Integrates with
mode enter/exit (enable on enter, disable on exit).

**Files:**
```
lua/turbo-debug/virtual_text.lua
```

**Acceptance criteria:**
- During a debug session, variable values appear as virtual text inline
- Virtual text uses comment syntax for the current filetype
- Changed values are highlighted differently
- Virtual text clears when exiting debug mode
- User can override settings via `opts.virtual_text`

**Test:** Manual. Debug a Python script, step through, verify virtual text
appears next to variable definitions. Exit debug mode, verify text clears.

**jj commit:** `virtual-text: inline variable values with sensible defaults`

---

### Task 8: Persistent breakpoints wiring

**What:** `lua/turbo-debug/breakpoints.lua` calls
`require("persistent-breakpoints").setup()` and maps `x`/`X` globally
(outside debug mode) to toggle/conditional breakpoint.

**Files:**
```
lua/turbo-debug/breakpoints.lua
tests/test_breakpoints.lua
```

**Acceptance criteria:**
- `x` toggles a breakpoint on the current line (sign appears in gutter)
- `X` prompts for a condition and sets a conditional breakpoint
- Both work outside of debug mode (no `<leader>d` needed first)
- Breakpoints persist: close Neovim, reopen, signs are still there
- Breakpoints are passed correctly to nvim-dap when a session starts

**Test:** Automated + manual. `tests/test_breakpoints.lua` verifies that
calling the breakpoint API places a sign. Manual test: set breakpoint,
quit Neovim, reopen, verify sign persists. Start debug session, verify
program stops at the breakpoint.

**jj commit:** `breakpoints: persistent breakpoints with global x/X mapping`

---

### Task 9: Watch from code window

**What:** Wire the `W` keybinding in debug mode to grab `<cexpr>` under
cursor (or visual selection) and insert it into the nvim-dap-ui watches
element programmatically.

**Files:**
```
lua/turbo-debug/mode.lua  (add watch action)
```

**Acceptance criteria:**
- `W` in normal mode in debug mode adds the expression under cursor to
  the watches panel
- `W` in visual mode adds the selected text to the watches panel
- The watch value updates live as you step
- No focus switch occurs — cursor stays in the code window

**Test:** Manual. Debug a Python script, place cursor on a variable, press
`W`, verify it appears in the watches panel. Select a complex expression
in visual mode, press `W`, verify it appears. Step, verify value updates.

**jj commit:** `watch: add expression under cursor to watches with W`

---

### Task 10: Hover and eval

**What:** Wire `K` to `require("dapui").eval()` (hover float with value
under cursor or visual selection). Wire `E` to
`require("dapui").float_element("repl")` (open REPL float for expression
evaluation).

**Files:**
```
lua/turbo-debug/mode.lua  (add hover + eval actions)
```

**Acceptance criteria:**
- `K` in normal mode shows a floating window with the value of the word
  under cursor
- `K` in visual mode shows the value of the selected expression
- `E` opens the REPL in a floating window for arbitrary expression input
- Both work during an active debug session

**Test:** Manual. Debug a Python script, hover a variable with `K`, verify
float shows value. Select `x + y` in visual mode, `K`, verify evaluated
result. Press `E`, type an expression in the REPL, verify output.

**jj commit:** `inspect: hover with K, eval with E`

---

### Task 11: Adapter configs — Python and Go

**What:** First two adapter configs. Python includes venv auto-detection.
Go includes delve auto-launch. Adapter loader in
`lua/turbo-debug/adapters/init.lua` handles registration and path
resolution.

**Files:**
```
lua/turbo-debug/adapters/init.lua
lua/turbo-debug/adapters/python.lua
lua/turbo-debug/adapters/go.lua
tests/test_adapters.lua
```

**Acceptance criteria:**
- Opening a `.py` file and pressing `<leader>d` then `c` launches debugpy
- If a virtualenv is active, debugpy uses it
- Opening a `.go` file and pressing `<leader>d` then `c` launches delve
- If the user already has `dap.configurations.python` set, we don't
  override it
- Path resolution checks PATH, then mason, then common system paths

**Test:** `tests/test_adapters.lua` verifies adapter tables are well-formed
and path resolution logic returns expected results for mock scenarios.
Manual: debug a real Python and Go program end-to-end.

**jj commit:** `adapters: python (with venv detection) and go (delve)`

---

### Task 12: Adapter configs — C/C++/Rust/Swift (codelldb)

**What:** Single adapter config shared across C, C++, Rust, and Swift.
Uses codelldb. Program picker via `vim.fn.input`.

**Files:**
```
lua/turbo-debug/adapters/c.lua
```

**Acceptance criteria:**
- Opening a `.c`, `.cpp`, `.rs`, or `.swift` file and debugging works
- Prompts for executable path on launch
- Finds codelldb via PATH or mason

**Test:** Manual. Compile a C program with `-g`, debug it, verify
breakpoints and stepping work.

**jj commit:** `adapters: c/cpp/rust/swift via codelldb`

---

### Task 13: Adapter configs — JavaScript/TypeScript

**What:** JS/TS adapter using `js-debug-adapter` (pwa-node). Shared across
`javascript`, `typescript`, `javascriptreact`, `typescriptreact` filetypes.

**Files:**
```
lua/turbo-debug/adapters/javascript.lua
```

**Acceptance criteria:**
- Opening a `.js` or `.ts` file and debugging launches pwa-node
- Launch file and attach configs both present
- Finds js-debug-adapter via PATH or mason

**Test:** Manual. Debug a Node.js script end-to-end.

**jj commit:** `adapters: javascript/typescript via js-debug-adapter`

---

### Task 14: Adapter configs — C#, Java, Kotlin

**What:** C# via netcoredbg. Java via java-debug-adapter. Kotlin via
kotlin-debug-adapter.

**Files:**
```
lua/turbo-debug/adapters/cs.lua
lua/turbo-debug/adapters/java.lua
lua/turbo-debug/adapters/kotlin.lua
```

**Acceptance criteria:**
- Each language launches its respective adapter when debugging
- Path resolution works for each
- Java config includes note in docs about nvim-jdtls for full support

**Test:** Manual per language where toolchain is available. Adapter table
structure verified in `tests/test_adapters.lua`.

**jj commit:** `adapters: csharp, java, kotlin`

---

### Task 15: Adapter configs — PHP, Ruby, Lua

**What:** PHP via php-debug (Xdebug listener on port 9003). Ruby via rdbg.
Lua via osv (optional, only if one-small-step-for-vimkind is available).

**Files:**
```
lua/turbo-debug/adapters/php.lua
lua/turbo-debug/adapters/ruby.lua
lua/turbo-debug/adapters/lua.lua
```

**Acceptance criteria:**
- PHP: listens for Xdebug on port 9003
- Ruby: launches rdbg in DAP mode
- Lua: only registers if osv is available, no error if it's not
- All path resolution works

**Test:** Manual per language. Lua adapter tested by checking graceful
skip when osv is not installed.

**jj commit:** `adapters: php, ruby, lua`

---

### Task 16: Vimdoc — complete help file

**What:** Write the full `doc/turbo-debug.txt` in vimdoc format. Covers
installation, configuration, all keybindings, all options, adapter
customization, and troubleshooting. Generate helptags.

**Files:**
```
doc/turbo-debug.txt
doc/tags                        (generated)
```

**Acceptance criteria:**
- `:help turbo-debug` opens the help file
- `:help turbo-debug.setup` jumps to the setup section
- `:help turbo-debug.keys` jumps to the keybindings section
- `:help turbo-debug.adapters` jumps to the adapters section
- Every public function and option is documented
- All tag references resolve correctly

**Test:** Open Neovim, run `:helptags doc/`, then `:help turbo-debug`
and verify all sections and tags work.

**jj commit:** `docs: complete vimdoc help file with all tags`

---

### Task 17: README — install, screenshots, quick start

**What:** Write README.md with: one-line install, feature list, screenshot
or ASCII diagram of the UI, keybinding table, minimal config, full config
example, supported languages table, FAQ, and links to `:help`.

**Files:**
```
README.md
CONTRIBUTING.md   (finalize)
```

**Acceptance criteria:**
- README renders correctly on GitHub
- One-line install is the first code block
- Keybinding table matches the spec
- Supported languages table matches the spec
- CONTRIBUTING.md explains how to add a new adapter config, how to run
  tests, and that we use jj not git

**Test:** Visual review on GitHub after push.

**jj commit:** `docs: readme, contributing guide`

---

### Task 18: End-to-end acceptance test

**What:** Run through the full success criteria checklist from the spec
for at least Python and one compiled language (C or Go). Fix any issues
discovered.

**Acceptance criteria:**
- All 11 success criteria steps pass for Python
- All 11 success criteria steps pass for C or Go
- No errors in `:messages` after a full debug session lifecycle
- Clean startup: no errors on `nvim --clean` with only turbo-debug

**Test:** Manual walkthrough of the full success criteria. Document results.

**jj commit:** `test: end-to-end acceptance for python and c/go`

---

### Task Summary

| #  | Task                        | Type     | Test method       |
|----|-----------------------------|----------|-------------------|
| 1  | Scaffold                    | Setup    | Manual smoke      |
| 2  | vim.pack dependencies       | Infra    | Manual smoke      |
| 3  | Config defaults + merge     | Core     | Automated         |
| 4  | Debug mode lifecycle        | Core     | Automated         |
| 5  | Help box                    | UI       | Automated         |
| 6  | nvim-dap-ui wiring          | UI       | Manual            |
| 7  | Virtual text wiring         | UI       | Manual            |
| 8  | Persistent breakpoints      | Core     | Automated+Manual  |
| 9  | Watch from code             | Feature  | Manual            |
| 10 | Hover and eval              | Feature  | Manual            |
| 11 | Adapters: Python, Go        | Adapter  | Automated+Manual  |
| 12 | Adapters: C/C++/Rust/Swift  | Adapter  | Manual            |
| 13 | Adapters: JS/TS             | Adapter  | Manual            |
| 14 | Adapters: C#, Java, Kotlin  | Adapter  | Manual            |
| 15 | Adapters: PHP, Ruby, Lua    | Adapter  | Manual            |
| 16 | Vimdoc help file            | Docs     | Manual            |
| 17 | README + CONTRIBUTING       | Docs     | Visual review     |
| 18 | End-to-end acceptance       | QA       | Manual walkthrough|

Each row = one `jj commit`. 18 commits total. The plugin is usable after
task 6 (basic debug mode with UI). It's feature-complete after task 15.
It's shippable after task 18.
