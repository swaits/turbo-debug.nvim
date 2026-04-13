local config = require("turbo-debug.config")
local mode = require("turbo-debug.mode")

local M = {}

function M.setup(opts)
  -- Self-defer if dependencies aren't yet on the runtimepath. This happens
  -- when the user calls `setup({...})` from their init.lua right after
  -- `vim.pack.add(..., turbo-debug)`: our plugin/turbo-debug.lua fires
  -- nested `vim.pack.add` calls for dap/dapui/persistent-breakpoints, but
  -- those nested adds only register the paths on the NEXT event loop tick
  -- — so a synchronous follow-up `require('persistent-breakpoints')`
  -- crashes with "module not found". `vim.schedule` lets the pack module
  -- finalize before we retry. `_setup_called` still gets set on the retry,
  -- so plugin/turbo-debug.lua's own deferred auto-setup correctly skips.
  if not pcall(require, "persistent-breakpoints") then
    vim.schedule(function() M.setup(opts) end)
    return
  end

  M._setup_called = true
  config.merge(opts)
  require("turbo-debug.breakpoints").setup()
  require("turbo-debug.adapters").setup()

  -- global toggle keybinding
  local toggle_key = config.opts.global_keys.toggle
  if toggle_key then
    vim.keymap.set("n", toggle_key, function() mode.toggle() end, {
      silent = true, desc = "Toggle debug mode",
    })
  end
end

function M.toggle()
  mode.toggle()
end

function M.active()
  return mode.is_active()
end

return M
