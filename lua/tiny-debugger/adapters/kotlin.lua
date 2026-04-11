local loader = require("tiny-debugger.adapters.init")

local M = {}

function M.register(dap)
  local kotlin_debug = loader.find_executable({ "kotlin-debug-adapter" })
  if not kotlin_debug then return end

  loader.register(dap, "kotlin", {
    type = "executable",
    command = kotlin_debug,
  }, {
    {
      type = "kotlin",
      request = "launch",
      name = "Launch main",
      mainClass = function()
        return vim.fn.input("Main class: ")
      end,
      projectRoot = "${workspaceFolder}",
    },
  }, { "kotlin" })
end

return M
