local config = require("turbo-debug.config")

local M = {}

local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/"

function M.find_executable(names)
  for _, name in ipairs(names) do
    if vim.fn.executable(name) == 1 then return name end
    local mason_path = mason_bin .. name
    if vim.fn.executable(mason_path) == 1 then return mason_path end
  end
end

function M.register(dap, name, adapter, configurations, filetypes)
  if dap.adapters[name] then return end
  dap.adapters[name] = adapter
  for _, ft in ipairs(filetypes) do
    dap.configurations[ft] = dap.configurations[ft] or configurations
  end
end

-- simple executable adapters (inlined — no separate files needed)
local function register_simple_adapters(dap)
  local simple = {
    {
      "netcoredbg",
      { "netcoredbg" },
      {
        type = "executable",
        args = { "--interpreter=vscode" },
      },
      {
        {
          type = "netcoredbg",
          request = "launch",
          name = "Launch .NET",
          program = function() return vim.fn.input("Path to DLL: ", vim.fn.getcwd() .. "/bin/Debug/", "file") end,
        },
      },
      { "cs", "fsharp" },
    },

    {
      "java",
      { "java-debug-adapter" },
      {
        type = "executable",
      },
      {
        {
          type = "java",
          request = "launch",
          name = "Launch class",
          mainClass = function() return vim.fn.input("Main class: ") end,
          cwd = "${workspaceFolder}",
        },
      },
      { "java" },
    },

    {
      "kotlin",
      { "kotlin-debug-adapter" },
      {
        type = "executable",
      },
      {
        {
          type = "kotlin",
          request = "launch",
          name = "Launch main",
          mainClass = function() return vim.fn.input("Main class: ") end,
          projectRoot = "${workspaceFolder}",
        },
      },
      { "kotlin" },
    },

    {
      "php",
      { "php-debug-adapter" },
      {
        type = "executable",
      },
      {
        {
          type = "php",
          request = "launch",
          name = "Listen for Xdebug",
          port = 9003,
        },
      },
      { "php" },
    },

    {
      "rdbg",
      { "rdbg" },
      {
        type = "server",
        port = "${port}",
        executable = { command = nil, args = { "-n", "--open", "--port", "${port}", "-c", "--", "ruby", "${file}" } },
      },
      {
        {
          type = "rdbg",
          request = "launch",
          name = "Launch file",
          command = "ruby",
          script = "${file}",
        },
        {
          type = "rdbg",
          request = "attach",
          name = "Attach",
          localfsMap = "${workspaceFolder}",
        },
      },
      { "ruby" },
    },

    {
      "mix_task",
      {
        "elixir-ls-debugger",
        "elixir-ls-debug-adapter",
        vim.fn.stdpath("data") .. "/mason/packages/elixir-ls/debugger.sh",
      },
      {
        type = "executable",
      },
      {
        {
          type = "mix_task",
          request = "launch",
          name = "mix test",
          task = "test",
          taskArgs = { "--trace" },
          startApps = true,
          projectDir = "${workspaceFolder}",
          requireFiles = { "test/**/test_helper.exs", "test/**/*_test.exs" },
        },
      },
      { "elixir" },
    },

    {
      "haskell",
      { "haskell-debug-adapter" },
      {
        type = "executable",
      },
      {
        {
          type = "haskell",
          request = "launch",
          name = "Launch file",
          workspace = "${workspaceFolder}",
          startup = "${file}",
          stopOnEntry = true,
          logFile = vim.fn.stdpath("data") .. "/haskell-dap.log",
          logLevel = "WARNING",
          ghciEnv = vim.empty_dict(),
          ghciPrompt = "H>>= ",
          ghciInitialPrompt = "Prelude>",
          ghciCmd = "cabal exec -- ghci-dap --interactive -i -i${workspaceFolder}",
        },
      },
      { "haskell" },
    },

    {
      "ocamlearlybird",
      { "ocamlearlybird" },
      {
        type = "executable",
        args = { "debug" },
      },
      {
        {
          type = "ocamlearlybird",
          request = "launch",
          name = "Launch bytecode",
          program = function()
            return vim.fn.input("Path to bytecode: ", vim.fn.getcwd() .. "/_build/default/", "file")
          end,
          stopOnEntry = false,
        },
      },
      { "ocaml" },
    },
  }

  for _, s in ipairs(simple) do
    local name, exe_names, adapter_tpl, configurations, filetypes = s[1], s[2], s[3], s[4], s[5]
    local exe = M.find_executable(exe_names)
    if exe then
      local adapter = vim.deepcopy(adapter_tpl)
      adapter.command = adapter.command or exe
      if adapter.executable then adapter.executable.command = exe end
      M.register(dap, name, adapter, configurations, filetypes)
    end
  end

  -- lua/neovim (osv) — optional, skip if not installed
  local ok, osv = pcall(require, "osv")
  if ok then
    M.register(dap, "nlua", {
      type = "server",
      host = "127.0.0.1",
      port = function() return osv.launch({ port = 0 }) end,
    }, { {
      type = "nlua",
      request = "attach",
      name = "Attach to running Neovim",
    } }, { "lua" })
  end
end

function M.setup()
  if not config.opts.builtin_adapters then return end

  local dap = require("dap")

  -- load adapters with non-trivial logic from separate files
  for _, name in ipairs({ "python", "go", "c", "javascript", "dart", "bash", "r" }) do
    local ok, adapter_mod = pcall(require, "turbo-debug.adapters." .. name)
    if ok and adapter_mod.register then adapter_mod.register(dap) end
  end

  -- register simple adapters inlined above
  register_simple_adapters(dap)

  -- apply user adapter overrides (last — wins over everything)
  for name, adapter_config in pairs(config.opts.adapters) do
    if adapter_config.adapter then dap.adapters[name] = adapter_config.adapter end
    if adapter_config.configurations then dap.configurations[name] = adapter_config.configurations end
  end
end

return M
