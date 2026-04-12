local loader = require("tiny-debugger.adapters.init")

local M = {}

function M.register(dap)
  local codelldb = loader.find_executable({ "codelldb" })
  if not codelldb then return end

  local adapter = {
    type = "server",
    port = "${port}",
    executable = {
      command = codelldb,
      args = { "--port", "${port}" },
    },
  }

  local configurations = {
    {
      type = "codelldb",
      request = "launch",
      name = "Launch executable",
      program = function()
        return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
      end,
      cwd = "${workspaceFolder}",
    },
  }

  loader.register(dap, "codelldb", adapter, configurations, { "c", "cpp", "rust", "swift" })
end

return M
