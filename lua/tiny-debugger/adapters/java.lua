local loader = require("tiny-debugger.adapters.init")

local M = {}

function M.register(dap)
  local java_debug = loader.find_executable({ "java-debug-adapter" })
  if not java_debug then return end

  loader.register(dap, "java", {
    type = "executable",
    command = java_debug,
  }, {
    {
      type = "java",
      request = "launch",
      name = "Launch class",
      mainClass = function()
        return vim.fn.input("Main class: ")
      end,
      cwd = "${workspaceFolder}",
    },
  }, { "java" })
end

return M
