local config = require("tiny-debugger.config")
local mode = require("tiny-debugger.mode")

local M = {}

function M.setup(opts)
  config.merge(opts)
  require("tiny-debugger.breakpoints").setup()
  require("tiny-debugger.adapters").setup()
end

function M.toggle()
  mode.toggle()
end

function M.active()
  return mode.is_active()
end

return M
