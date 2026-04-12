local loader = require("tiny-debugger.adapters.init")

local M = {}

local function find_rust_binary()
  -- build and capture artifact paths
  vim.notify("cargo build ...", vim.log.levels.INFO)
  local output = vim.fn.system("cargo build --message-format=json 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    vim.notify("cargo build failed", vim.log.levels.ERROR)
    return nil
  end

  local executables = {}
  for line in output:gmatch("[^\n]+") do
    local ok, msg = pcall(vim.json.decode, line)
    if ok and msg.reason == "compiler-artifact" and msg.executable then
      table.insert(executables, msg.executable)
    end
  end

  if #executables == 1 then
    return executables[1]
  elseif #executables > 1 then
    local choice = vim.fn.inputlist(
      vim.list_extend({ "Select executable:" },
        vim.tbl_map(function(e) return "  " .. vim.fn.fnamemodify(e, ":t") end, executables))
    )
    return choice > 0 and executables[choice] or nil
  end

  -- fallback: prompt
  return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
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

  -- register adapter once
  if not dap.adapters.codelldb then
    dap.adapters.codelldb = adapter
  end

  -- C/C++/Swift: prompt for executable path
  local prompt_config = {
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
  for _, ft in ipairs({ "c", "cpp", "swift" }) do
    dap.configurations[ft] = dap.configurations[ft] or prompt_config
  end

  -- Rust: cargo build + auto-find binary
  dap.configurations.rust = dap.configurations.rust or {
    {
      type = "codelldb",
      request = "launch",
      name = "Cargo build & launch",
      program = find_rust_binary,
      cwd = "${workspaceFolder}",
    },
  }
end

return M
