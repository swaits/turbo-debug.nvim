local loader = require("turbo-debug.adapters.init")

local M = {}

-- vscDebugger is an R package, not a standalone binary. It must be installed
-- in the user's R library (install.packages("vscDebugger") or remotes::install_github).
-- Silently skip registration if it's missing — matches the "no noise when
-- prereqs missing" invariant used by the other adapters.
local function has_vsc_debugger()
  if vim.fn.executable("Rscript") ~= 1 then return false end
  vim.fn.system({
    "Rscript",
    "-e",
    "if (!requireNamespace('vscDebugger', quietly=TRUE)) quit(status=1)",
  })
  return vim.v.shell_error == 0
end

function M.register(dap)
  local R = loader.find_executable({ "R" })
  if not R then return end
  if not has_vsc_debugger() then return end

  loader.register(dap, "r", {
    type = "executable",
    command = R,
    args = { "-e", "vscDebugger::.vsc.listenForDAP()" },
  }, {
    {
      type = "r",
      request = "launch",
      name = "Launch R file",
      program = "${file}",
      cwd = "${workspaceFolder}",
    },
  }, { "r", "rmd" })
end

return M
