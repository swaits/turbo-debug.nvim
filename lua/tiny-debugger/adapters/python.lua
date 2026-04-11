local loader = require("tiny-debugger.adapters.init")

local M = {}

local function find_python()
  -- check active virtualenv
  local venv = vim.env.VIRTUAL_ENV
  if venv then
    local path = venv .. "/bin/python"
    if vim.fn.executable(path) == 1 then return path end
  end

  -- check conda
  local conda = vim.env.CONDA_PREFIX
  if conda then
    local path = conda .. "/bin/python"
    if vim.fn.executable(path) == 1 then return path end
  end

  -- probe common venv directories relative to cwd
  local cwd = vim.fn.getcwd()
  for _, dir in ipairs({ ".venv", "venv", "env", ".env" }) do
    local path = cwd .. "/" .. dir .. "/bin/python"
    if vim.fn.executable(path) == 1 then return path end
  end

  -- fallback to system python
  if vim.fn.executable("python3") == 1 then return "python3" end
  if vim.fn.executable("python") == 1 then return "python" end
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
