local loader = require("turbo-debug.adapters.init")

local M = {}

function M.register(dap)
  local dlv = loader.find_executable({ "dlv" })
  if not dlv then return end

  loader.register(dap, "delve", {
    type = "server",
    port = "${port}",
    executable = {
      command = dlv,
      args = { "dap", "-l", "127.0.0.1:${port}" },
    },
  }, {
    {
      type = "delve",
      request = "launch",
      name = "Launch file",
      program = "${file}",
    },
    {
      type = "delve",
      request = "launch",
      name = "Launch package",
      program = "./${relativeFileDirname}",
    },
  }, { "go" })
end

return M
