local config = require("tiny-debugger.config")

local M = {}

local win_id = nil
local buf_id = nil

local key_labels = {
  continue = "Continue",
  step_over = "Step over",
  step_into = "Step into",
  step_out = "Step out",
  run_to_cursor = "Run to cursor",
  breakpoint = "Toggle breakpoint",
  cond_breakpoint = "Conditional breakpoint",
  watch = "Watch expression",
  hover = "Hover / inspect",
  eval = "Eval in REPL",
  terminate = "Quit debugging",
  restart = "Restart session",
  help = "Show this help",
}

-- ordered list of key names for consistent display
local key_order = {
  "continue", "step_over", "step_into", "step_out", "run_to_cursor",
  "breakpoint", "cond_breakpoint", "watch", "hover", "eval",
  "terminate", "restart", "help",
}

local function build_lines()
  local lines = { " tiny-debugger keybindings", "" }
  local keys = config.opts.keys
  for _, name in ipairs(key_order) do
    local key = keys[name]
    if key then
      local label = key_labels[name] or name
      table.insert(lines, string.format("  %s  %s", key, label))
    end
  end
  table.insert(lines, "")
  return lines
end

local function calc_width(lines)
  local max = 0
  for _, line in ipairs(lines) do
    max = math.max(max, #line)
  end
  return max + 2
end

function M.close()
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    vim.api.nvim_win_close(win_id, true)
  end
  win_id = nil
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    vim.api.nvim_buf_delete(buf_id, { force = true })
  end
  buf_id = nil
end

function M.open()
  M.close()

  local lines = build_lines()
  local width = calc_width(lines)
  local height = #lines

  buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  vim.bo[buf_id].modifiable = false
  vim.bo[buf_id].bufhidden = "wipe"

  local editor_width = vim.o.columns
  local editor_height = vim.o.lines

  win_id = vim.api.nvim_open_win(buf_id, false, {
    relative = "editor",
    anchor = "SE",
    row = editor_height - 2,
    col = editor_width,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
  })

  -- auto-close on next keypress
  vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "CmdlineEnter" }, {
    once = true,
    callback = function()
      M.close()
    end,
  })
end

function M.is_open()
  return win_id ~= nil and vim.api.nvim_win_is_valid(win_id)
end

return M
