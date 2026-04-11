local config = require("tiny-debugger.config")

local M = {}

local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/"

function M.find_executable(names)
  for _, name in ipairs(names) do
    -- check PATH
    if vim.fn.executable(name) == 1 then
      return name
    end
    -- check mason
    local mason_path = mason_bin .. name
    if vim.fn.executable(mason_path) == 1 then
      return mason_path
    end
  end
  return nil
end

function M.register(dap, name, adapter, configurations, filetypes)
  -- don't override user-configured adapters
  if dap.adapters[name] then return end

  dap.adapters[name] = adapter

  for _, ft in ipairs(filetypes) do
    if not dap.configurations[ft] then
      dap.configurations[ft] = configurations
    end
  end
end

function M.setup()
  if not config.opts.builtin_adapters then return end

  local dap = require("dap")

  -- load built-in adapter modules
  local adapters = {
    "python", "go", "c", "javascript", "cs", "java", "kotlin", "php", "ruby", "lua",
  }

  for _, name in ipairs(adapters) do
    local ok, adapter_mod = pcall(require, "tiny-debugger.adapters." .. name)
    if ok and adapter_mod.register then
      adapter_mod.register(dap)
    end
  end

  -- apply user adapter overrides
  for name, adapter_config in pairs(config.opts.adapters) do
    if adapter_config.adapter then
      dap.adapters[name] = adapter_config.adapter
    end
    if adapter_config.configurations then
      dap.configurations[name] = adapter_config.configurations
    end
  end
end

return M
