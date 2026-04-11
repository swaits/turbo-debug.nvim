local loader = require("tiny-debugger.adapters.init")

local M = {}

function M.register(dap)
  local netcoredbg = loader.find_executable({ "netcoredbg" })
  if not netcoredbg then return end

  loader.register(dap, "netcoredbg", {
    type = "executable",
    command = netcoredbg,
    args = { "--interpreter=vscode" },
  }, {
    {
      type = "netcoredbg",
      request = "launch",
      name = "Launch .NET",
      program = function()
        return vim.fn.input("Path to DLL: ", vim.fn.getcwd() .. "/bin/Debug/", "file")
      end,
    },
  }, { "cs" })
end

return M
