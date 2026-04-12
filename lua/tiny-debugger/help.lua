local config = require("tiny-debugger.config")

local M = {}

local win_id = nil
local buf_id = nil
local timer = nil

local modal_info = {
  { "continue", "Continue" },
  { "step_over", "Step over" },
  { "step_into", "Step into" },
  { "step_out", "Step out" },
  { "run_to_cursor", "Run to cursor" },
  { "watch", "Watch expression" },
  { "hover", "Hover / inspect" },
  { "eval", "Eval in REPL" },
  { "terminate", "Quit debugging" },
  { "restart", "Restart session" },
}

local global_info = {
  { "toggle", "Toggle debug mode" },
  { "breakpoint", "Toggle breakpoint" },
  { "cond_breakpoint", "Conditional breakpoint" },
  { "clear_breakpoints", "Clear all breakpoints" },
}

local function build_content()
  local lines = { " tiny-debugger", "" }
  local width = #lines[1]

  local function add(key, label)
    local line = string.format("  %-12s %s", key, label)
    lines[#lines + 1] = line
    if #line > width then width = #line end
  end

  lines[#lines + 1] = " Debug mode:"
  for _, pair in ipairs(modal_info) do
    local key = config.opts.keys[pair[1]]
    if key then add(key, pair[2]) end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = " Always available:"
  for _, pair in ipairs(global_info) do
    local key = config.opts.global_keys[pair[1]]
    if key then add(key, pair[2]) end
  end

  -- highlight line at the bottom
  local help_key = config.opts.keys.help or "?"
  lines[#lines + 1] = ""
  lines[#lines + 1] = " Press " .. help_key .. " for help"
  lines[#lines + 1] = ""

  return lines, width + 2
end

function M.close()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
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

  local lines, width = build_content()
  local height = #lines

  buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  -- highlight the "Press ? for help" line
  local hl_line = height - 2
  vim.api.nvim_buf_add_highlight(buf_id, -1, "Bold", hl_line, 0, -1)

  vim.bo[buf_id].modifiable = false
  vim.bo[buf_id].bufhidden = "wipe"

  -- center the float
  local ed_w = vim.o.columns
  local ed_h = vim.o.lines
  local row = math.floor((ed_h - height) / 2)
  local col = math.floor((ed_w - width) / 2)

  win_id = vim.api.nvim_open_win(buf_id, false, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
  })

  -- auto-close after 2 seconds
  timer = vim.uv.new_timer()
  timer:start(2000, 0, vim.schedule_wrap(function() M.close() end))
end

function M.is_open()
  return win_id ~= nil and vim.api.nvim_win_is_valid(win_id)
end

return M
