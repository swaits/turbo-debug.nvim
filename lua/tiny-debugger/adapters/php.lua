local loader = require("tiny-debugger.adapters.init")

local M = {}

function M.register(dap)
  local php_debug = loader.find_executable({ "php-debug-adapter" })
  if not php_debug then return end

  loader.register(dap, "php", {
    type = "executable",
    command = php_debug,
  }, {
    {
      type = "php",
      request = "launch",
      name = "Listen for Xdebug",
      port = 9003,
    },
  }, { "php" })
end

return M
