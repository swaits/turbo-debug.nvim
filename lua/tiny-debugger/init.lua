local config = require("tiny-debugger.config")
local mode = require("tiny-debugger.mode")
local breakpoints = require("tiny-debugger.breakpoints")
local adapters = require("tiny-debugger.adapters")

local M = {}

function M.setup(opts)
  config.merge(opts)
  breakpoints.setup()
  adapters.setup()
end

function M.toggle()
  mode.toggle()
end

function M.active()
  return mode.is_active()
end

return M
