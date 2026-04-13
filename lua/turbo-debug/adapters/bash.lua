local loader = require("turbo-debug.adapters.init")

local M = {}

function M.register(dap)
  local exe = loader.find_executable({ "bash-debug-adapter" })
  if not exe then return end

  local bashdb_dir = vim.fn.stdpath("data") .. "/mason/packages/bash-debug-adapter/extension/bashdb_dir"
  if vim.fn.isdirectory(bashdb_dir) == 0 then bashdb_dir = nil end

  loader.register(dap, "bashdb", {
    type = "executable",
    command = exe,
    name = "bashdb",
  }, {
    {
      type = "bashdb",
      request = "launch",
      name = "Launch file",
      showDebugOutput = true,
      pathBashdb = bashdb_dir and (bashdb_dir .. "/bashdb") or "bashdb",
      pathBashdbLib = bashdb_dir,
      trace = true,
      file = "${file}",
      program = "${file}",
      cwd = "${workspaceFolder}",
      pathCat = "cat",
      pathBash = "/bin/bash",
      pathMkfifo = "mkfifo",
      pathPkill = "pkill",
      args = {},
      env = {},
      terminalKind = "integrated",
    },
  }, { "sh", "bash" })
end

return M
