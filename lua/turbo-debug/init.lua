local config = require("turbo-debug.config")
local mode = require("turbo-debug.mode")

local M = {}

function M.setup(opts)
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
