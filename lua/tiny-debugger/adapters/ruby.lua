local loader = require("tiny-debugger.adapters.init")

local M = {}

function M.register(dap)
  local rdbg = loader.find_executable({ "rdbg" })
  if not rdbg then return end

  loader.register(dap, "rdbg", {
    type = "server",
    port = "${port}",
    executable = {
      command = rdbg,
      args = { "-n", "--open", "--port", "${port}", "-c", "--", "ruby", "${file}" },
    },
  }, {
    {
      type = "rdbg",
      request = "launch",
      name = "Launch file",
      command = "ruby",
      script = "${file}",
    },
    {
      type = "rdbg",
      request = "attach",
      name = "Attach",
      localfsMap = "${workspaceFolder}",
    },
  }, { "ruby" })
end

return M
