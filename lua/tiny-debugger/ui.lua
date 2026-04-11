local config = require("tiny-debugger.config")

local M = {}

local initialized = false

local function ensure_setup()
  if initialized then return end
  initialized = true

  local dapui = require("dapui")
  dapui.setup(config.opts.dapui)

  -- auto-exit debug mode when session ends
  local dap = require("dap")
  local mode = require("tiny-debugger.mode")

  dap.listeners.after.event_terminated["tiny-debugger"] = function()
    if mode.is_active() then
      mode.exit()
    end
  end

  dap.listeners.after.event_exited["tiny-debugger"] = function()
    if mode.is_active() then
      mode.exit()
    end
  end
end

function M.open()
  ensure_setup()
  require("dapui").open()
end

function M.close()
  if initialized then
    require("dapui").close()
  end
end

return M
