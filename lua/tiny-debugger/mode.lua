local config = require("tiny-debugger.config")

local M = {}

local active = false
local stashed_maps = {}

local function stash_mapping(buf, lhs)
  local maps = vim.api.nvim_buf_get_keymap(buf, "n")
  for _, map in ipairs(maps) do
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
      vim.keymap.set("n", lhs, rhs, {
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

-- actions table: key name → function
-- populated by other modules via M.register_action
local actions = {}

function M.register_action(name, fn)
  actions[name] = fn
end

-- default actions that map directly to dap calls
local function setup_default_actions()
  local dap = require("dap")
  actions.continue = function() dap.continue() end
  actions.step_over = function() dap.step_over() end
  actions.step_into = function() dap.step_into() end
  actions.step_out = function() dap.step_out() end
  actions.run_to_cursor = function() dap.run_to_cursor() end
  actions.terminate = function()
    dap.terminate()
    M.exit()
  end
  actions.restart = function() dap.restart() end
end

local function set_keymaps(buf)
  local keys = config.opts.keys
  for name, key in pairs(keys) do
    if key and actions[name] then
      stash_mapping(buf, key)
      vim.keymap.set("n", key, actions[name], { buffer = buf, silent = true, desc = "tiny-debugger: " .. name })
    end
  end
end

local function clear_keymaps(buf)
  local keys = config.opts.keys
  for name, key in pairs(keys) do
    if key and actions[name] then
      pcall(vim.keymap.del, "n", key, { buffer = buf })
      restore_mapping(buf, key)
    end
  end
  stashed_maps = {}
end

local saved_cursor_hl = nil

local function set_cursor_highlight()
  saved_cursor_hl = vim.api.nvim_get_hl(0, { name = "Cursor" })
  vim.api.nvim_set_hl(0, "Cursor", { bg = "#ff6600", fg = "#000000" })
end

local function restore_cursor_highlight()
  if saved_cursor_hl then
    vim.api.nvim_set_hl(0, "Cursor", saved_cursor_hl)
    saved_cursor_hl = nil
  else
    vim.api.nvim_set_hl(0, "Cursor", {})
  end
end

function M.enter()
  if active then return end
  active = true

  setup_default_actions()

  local buf = vim.api.nvim_get_current_buf()
  set_keymaps(buf)
  set_cursor_highlight()
end

function M.exit()
  if not active then return end
  active = false

  local buf = vim.api.nvim_get_current_buf()
  clear_keymaps(buf)
  restore_cursor_highlight()
end

function M.toggle()
  if active then
    M.exit()
  else
    M.enter()
  end
end

function M.is_active()
  return active
end

return M
