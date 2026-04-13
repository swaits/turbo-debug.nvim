local loader = require("turbo-debug.adapters.init")

local M = {}

function M.register(dap)
  local js_debug = loader.find_executable({ "js-debug-adapter" })
  if not js_debug then return end

  local adapter = {
    type = "server",
    port = "${port}",
    executable = {
      command = js_debug,
      args = { "${port}" },
    },
  }

  local configurations = {
    {
      type = "pwa-node",
      request = "launch",
      name = "Launch file",
      program = "${file}",
      cwd = "${workspaceFolder}",
    },
    {
      type = "pwa-node",
      request = "attach",
      name = "Attach",
      processId = function() return require("dap.utils").pick_process() end,
      cwd = "${workspaceFolder}",
    },
  }

  loader.register(dap, "pwa-node", adapter, configurations, {
    "javascript",
    "typescript",
    "javascriptreact",
    "typescriptreact",
  })
end

return M
