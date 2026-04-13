local loader = require("turbo-debug.adapters.init")

local M = {}

function M.register(dap)
  local dart = loader.find_executable({ "dart" })
  if not dart then return end

  local configs = {
    {
      type = "dart",
      request = "launch",
      name = "Launch Dart file",
      program = "${file}",
      cwd = "${workspaceFolder}",
      toolArgs = { "--enable-vm-service" },
    },
  }

  local flutter = loader.find_executable({ "flutter" })
  if flutter then
    if not dap.adapters.flutter then
      dap.adapters.flutter = {
        type = "executable",
        command = flutter,
        args = { "debug_adapter" },
      }
    end
    table.insert(configs, {
      type = "flutter",
      request = "launch",
      name = "Launch Flutter app",
      program = "lib/main.dart",
      cwd = "${workspaceFolder}",
      flutterMode = "debug",
    })
  end

  loader.register(dap, "dart", {
    type = "executable",
    command = dart,
    args = { "debug_adapter" },
  }, configs, { "dart" })
end

return M
