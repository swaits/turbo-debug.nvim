# Contributing to tiny-debugger.nvim

## Source Control

We use **jj** (Jujutsu), not git. All commits should be made with `jj commit`.

## Adding a New Adapter

1. Create `lua/tiny-debugger/adapters/<language>.lua`
2. Implement a `register(dap)` function that calls `loader.register()`
3. Add the module name to the adapters list in `lua/tiny-debugger/adapters/init.lua`
4. Add the language to the README and vimdoc tables

Example adapter (minimal):

```lua
local loader = require("tiny-debugger.adapters.init")

local M = {}

function M.register(dap)
  local binary = loader.find_executable({ "my-debug-adapter" })
  if not binary then return end

  loader.register(dap, "my-adapter", {
    type = "executable",
    command = binary,
  }, {
    {
      type = "my-adapter",
      request = "launch",
      name = "Launch file",
      program = "${file}",
    },
  }, { "mylang" })
end

return M
```

## Running Tests

```sh
nvim --headless -u tests/minimal_init.lua -c 'luafile tests/test_config.lua' -c 'qa!'
nvim --headless -u tests/minimal_init.lua -c 'luafile tests/test_mode.lua' -c 'qa!'
nvim --headless -u tests/minimal_init.lua -c 'luafile tests/test_keys.lua' -c 'qa!'
nvim --headless -u tests/minimal_init.lua -c 'luafile tests/test_help.lua' -c 'qa!'
nvim --headless -u tests/minimal_init.lua -c 'luafile tests/test_breakpoints.lua' -c 'qa!'
nvim --headless -u tests/minimal_init.lua -c 'luafile tests/test_adapters.lua' -c 'qa!'
```

## Code Style

- Clean, readable Lua. No metaprogramming tricks.
- Every file should be short enough to read in one sitting.
- No abstraction for abstraction's sake.
- If a plugin does something we can do in <50 lines, we don't add the dependency.

## Dependencies

We depend on exactly five plugins (managed via `vim.pack.add`):

- nvim-dap
- nvim-dap-ui
- nvim-nio
- nvim-dap-virtual-text
- persistent-breakpoints.nvim

No language-specific plugin dependencies. Adapter configs are inlined as plain
Lua tables.
