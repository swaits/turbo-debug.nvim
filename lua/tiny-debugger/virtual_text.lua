local config = require("tiny-debugger.config")

local M = {}

local initialized = false

function M.setup()
  if initialized then return end
  initialized = true
  require("nvim-dap-virtual-text").setup(config.opts.virtual_text)
end

function M.enable()
  M.setup()
  require("nvim-dap-virtual-text").enable()
end

function M.disable()
  if initialized then
    require("nvim-dap-virtual-text").disable()
  end
end

return M
