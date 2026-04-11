local loader = require("tiny-debugger.adapters.init")

local M = {}

function M.register(dap)
  -- osv (one-small-step-for-vimkind) is optional — skip gracefully if not installed
  local ok, osv = pcall(require, "osv")
  if not ok then return end

  loader.register(dap, "nlua", {
    type = "server",
    host = "127.0.0.1",
    port = function()
      return osv.launch({ port = 0 })
    end,
  }, {
    {
      type = "nlua",
      request = "attach",
      name = "Attach to running Neovim",
    },
  }, { "lua" })
end

return M
