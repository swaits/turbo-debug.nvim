local config = require("tiny-debugger.config")
local help = require("tiny-debugger.help")

local M = {}

local active = false
local active_buf = nil
local active_win = nil
local stashed_maps = {}
local saved_winbar = nil

-- one-time dap-ui and virtual-text initialization
local dapui_initialized = false
local vt_initialized = false

local function ensure_dapui()
  if dapui_initialized then return end
  dapui_initialized = true
  require("dapui").setup(config.opts.dapui)

  local dap = require("dap")
  dap.listeners.after.event_terminated["tiny-debugger"] = function()
    if active then M.exit() end
  end
  dap.listeners.after.event_exited["tiny-debugger"] = function()
    if active then M.exit() end
  end

  -- set winbar titles on dapui panels (REPL gets controls toolbar from dapui)
  local titles = {
    dapui_scopes = " Scopes",
    dapui_watches = " Watches",
    dapui_stacks = " Call Stack",
    dapui_console = " Console",
    dapui_breakpoints = " Breakpoints",
  }
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "dapui_*",
    callback = function(args)
      local title = titles[vim.bo[args.buf].filetype]
      if title then
        vim.schedule(function()
          local win = vim.fn.bufwinid(args.buf)
          if win ~= -1 then vim.wo[win].winbar = title end
        end)
      end
    end,
  })
end

local function ensure_vt()
  if vt_initialized then return end
  vt_initialized = true
  require("nvim-dap-virtual-text").setup(config.opts.virtual_text)
end

-- keymap stash/restore

local function stash_mapping(buf, lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if map.lhs == lhs then
      stashed_maps[lhs] = map
      return
    end
  end
  stashed_maps[lhs] = nil
end

local function restore_mapping(buf, lhs)
  local map = stashed_maps[lhs]
  if map then
    local rhs = map.rhs or map.callback
    if rhs then
      pcall(vim.keymap.set, "n", lhs, rhs, {
        buffer = buf,
        silent = map.silent == 1,
        noremap = map.noremap == 1,
        expr = map.expr == 1,
        desc = map.desc,
      })
    end
  else
    pcall(vim.keymap.del, "n", lhs, { buffer = buf })
  end
end

-- actions (set up once)

local actions = {}
local visual_actions = { watch = true, hover = true }

local function setup_actions()
  if next(actions) then return end
  local dap = require("dap")
  actions.continue = function() dap.continue() end
  actions.step_over = function() dap.step_over() end
  actions.step_into = function() dap.step_into() end
  actions.step_out = function() dap.step_out() end
  actions.run_to_cursor = function() dap.run_to_cursor() end
  actions.terminate = function() dap.terminate(); M.exit() end
  actions.restart = function() dap.restart() end
  actions.help = function()
    if help.is_open() then help.close() else help.open() end
  end
  actions.watch = function()
    local expr
    if vim.fn.mode() == "v" or vim.fn.mode() == "V" then
      vim.cmd('noautocmd normal! "vy')
      expr = vim.fn.getreg("v")
    else
      expr = vim.fn.expand("<cexpr>")
    end
    if expr and expr ~= "" then
      require("dapui").elements.watches.add(expr)
    end
  end
  actions.hover = function() require("dapui").eval() end
  actions.eval = function() require("dapui").float_element("repl") end
end

-- keymap lifecycle

local function set_keymaps(buf)
  local keys = config.opts.keys
  for name, key in pairs(keys) do
    if key and actions[name] then
      stash_mapping(buf, key)
      vim.keymap.set("n", key, actions[name], { buffer = buf, silent = true, desc = "tiny-debugger: " .. name })
      if visual_actions[name] then
        vim.keymap.set("v", key, actions[name], { buffer = buf, silent = true, desc = "tiny-debugger: " .. name })
      end
    end
  end
end

local function clear_keymaps(buf)
  local keys = config.opts.keys
  for name, key in pairs(keys) do
    if key and actions[name] then
      pcall(vim.keymap.del, "n", key, { buffer = buf })
      if visual_actions[name] then
        pcall(vim.keymap.del, "v", key, { buffer = buf })
      end
      restore_mapping(buf, key)
    end
  end
  stashed_maps = {}
end

-- debug mode chrome

local function set_debug_chrome()
  active_win = vim.api.nvim_get_current_win()
  saved_winbar = vim.wo[active_win].winbar
  vim.wo[active_win].winbar = "%#DiagnosticError# 🐛 DEBUG %* %f"

  vim.api.nvim_set_hl(0, "Cursor", { bg = "#ff6600", fg = "#000000" })
end

local function clear_debug_chrome()
  if active_win and vim.api.nvim_win_is_valid(active_win) then
    vim.wo[active_win].winbar = saved_winbar or ""
  end
  active_win = nil
  saved_winbar = nil

  vim.api.nvim_set_hl(0, "Cursor", {})
end

-- public API

function M.enter()
  if active then return end
  active = true
  setup_actions()

  active_buf = vim.api.nvim_get_current_buf()
  set_keymaps(active_buf)
  set_debug_chrome()

  ensure_dapui()
  require("dapui").open()

  ensure_vt()
  require("nvim-dap-virtual-text").enable()

  if config.opts.help_on_enter then
    help.open()
  end
end

function M.exit()
  if not active then return end
  active = false

  clear_keymaps(active_buf or vim.api.nvim_get_current_buf())
  active_buf = nil
  clear_debug_chrome()
  help.close()

  if dapui_initialized then require("dapui").close() end
  if vt_initialized then require("nvim-dap-virtual-text").disable() end
end

function M.toggle()
  if active then M.exit() else M.enter() end
end

function M.is_active()
  return active
end

return M
