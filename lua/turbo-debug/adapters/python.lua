local loader = require("turbo-debug.adapters.init")

local M = {}

-- Try in order: active virtualenv, conda, common local venv dirs, system.
-- First executable match wins. Using a single ordered list keeps the probe
-- sequence explicit (ipairs preserves numeric order).
local function find_python()
  local candidates = {}
  if vim.env.VIRTUAL_ENV then candidates[#candidates + 1] = vim.env.VIRTUAL_ENV .. "/bin/python" end
  if vim.env.CONDA_PREFIX then candidates[#candidates + 1] = vim.env.CONDA_PREFIX .. "/bin/python" end
  local cwd = vim.fn.getcwd()
  for _, dir in ipairs({ ".venv", "venv", "env", ".env" }) do
    candidates[#candidates + 1] = cwd .. "/" .. dir .. "/bin/python"
  end
  candidates[#candidates + 1] = "python3"
  candidates[#candidates + 1] = "python"
  for _, p in ipairs(candidates) do
    if vim.fn.executable(p) == 1 then return p end
  end
  return nil
end

function M.register(dap)
  local python = find_python()
  if not python then return end

  loader.register(dap, "debugpy", {
    type = "executable",
    command = python,
    args = { "-m", "debugpy.adapter" },
  }, {
    {
      type = "debugpy",
      request = "launch",
      name = "Launch file",
      program = "${file}",
      pythonPath = function() return find_python() end,
    },
  }, { "python" })
end

return M
