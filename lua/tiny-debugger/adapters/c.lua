local loader = require("tiny-debugger.adapters.init")

local M = {}

local function find_rust_binary()
  vim.notify("cargo build ...", vim.log.levels.INFO)
  local output = vim.fn.system("cargo build --message-format=json")
  if vim.v.shell_error ~= 0 then
    -- extract the human-readable error lines (non-json)
    local errors = {}
    for line in output:gmatch("[^\n]+") do
      if not line:match("^{") then errors[#errors + 1] = line end
    end
    vim.notify("cargo build failed:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
    return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
  end

  local executables = {}
  for line in output:gmatch("[^\n]+") do
    local ok, msg = pcall(vim.json.decode, line)
    if ok and msg.reason == "compiler-artifact" and msg.executable then
      executables[#executables + 1] = msg.executable
    end
  end

  if #executables == 1 then
    return executables[1]
  elseif #executables > 1 then
    local items = { "Select executable:" }
    for i, e in ipairs(executables) do
      items[i + 1] = i .. ". " .. vim.fn.fnamemodify(e, ":t")
    end
    local choice = vim.fn.inputlist(items)
    if choice > 0 and choice <= #executables then
      return executables[choice]
    end
  end

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
