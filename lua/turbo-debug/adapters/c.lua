local loader = require("turbo-debug.adapters.init")

local M = {}

local function pick_executable(executables)
  local co = coroutine.running()
  if not co then return executables[1] end
  vim.ui.select(executables, {
    prompt = "Select executable",
    format_item = function(path) return vim.fn.fnamemodify(path, ":t") end,
  }, function(choice) coroutine.resume(co, choice) end)
  return coroutine.yield()
end

local function cargo_build_and_pick()
  vim.notify("cargo build ...")
  local output = vim.fn.system("cargo build --message-format=json")
  if vim.v.shell_error ~= 0 then
    local errors = {}
    for line in output:gmatch("[^\n]+") do
      if not line:match("^{") then errors[#errors + 1] = line end
    end
    vim.notify("cargo build failed:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
    return nil
  end

  local executables = {}
  for line in output:gmatch("[^\n]+") do
    local ok, msg = pcall(vim.json.decode, line)
    if ok and msg.reason == "compiler-artifact" and msg.executable then
      executables[#executables + 1] = msg.executable
    end
  end

  if #executables == 0 then return nil end
  if #executables == 1 then return executables[1] end
  return pick_executable(executables)
end

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

  if not dap.adapters.codelldb then dap.adapters.codelldb = adapter end

  -- C/C++/Swift: pick from compiled executables in cwd
  local prompt_config = {
    {
      type = "codelldb",
      request = "launch",
      name = "Launch executable",
      program = function() return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file") end,
      cwd = "${workspaceFolder}",
    },
  }
  for _, ft in ipairs({ "c", "cpp", "swift", "zig", "nim", "crystal" }) do
    dap.configurations[ft] = dap.configurations[ft] or prompt_config
  end

  -- Rust: cargo build + picker
  dap.configurations.rust = dap.configurations.rust
    or {
      {
        type = "codelldb",
        request = "launch",
        name = "Cargo build & launch",
        program = cargo_build_and_pick,
        cwd = "${workspaceFolder}",
      },
    }
end

return M
