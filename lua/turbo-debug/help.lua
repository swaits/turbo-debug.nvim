local config = require("turbo-debug.config")

local M = {}

local win_id = nil
local buf_id = nil

-- Each entry:
--   { action,      key_letter, pre,              post }
-- The formatted line is:  "  <pre>(<key>)<post>"  with <key> taken from the
-- config.opts.keys[action] lookup. Highlight spans are computed against
-- the actual key letter in the final line.
local flow = {
  { "continue", "c", "(", ")ontinue" },
  { "step_over", "s", "(", ")tep over" },
  { "step_into", "d", "(", ")escend into" },
  { "step_out", "r", "(", ")eturn out" },
  { "run_to_cursor", "C", "run to (", ") cursor" },
  { "restart", "R", "(", ")estart session" },
  { "terminate", "q", "(", ")uit debugging" },
}

local breakpoints = {
  { "breakpoint", "x", "(", ") toggle breakpoint" },
  { "cond_breakpoint", "X", "(", ") conditional breakpoint" },
  { "clear_breakpoints", "D", "(", ")elete all breakpoints" },
}

local inspect = {
  { "watch", "W", "(", ")atch expression" },
  { "hover", "K", "(", ") hover / inspect" },
  { "eval", "E", "(", ")val in REPL" },
}

local meta = {
  { "help", "?", "(", ") this popup" },
}

local globals = {
  { "breakpoint", "toggle breakpoint" },
  { "cond_breakpoint", "conditional breakpoint" },
  { "clear_breakpoints", "delete all breakpoints" },
}

local dapui_panes = {
  { "<CR>", "expand / jump to target" },
  { "o", "open target (jump to frame / breakpoint)" },
  { "e", "edit (watches)" },
  { "d", "remove (watches)" },
  { "r", "send to REPL" },
  { "t", "toggle subtle frames (call stack)" },
}

-- ▶ U+25B6, ● U+25CF, ◉ U+25C9, ◆ U+25C6, ❯ U+276F, ≡ U+2261
local ICON_FLOW = "\xe2\x96\xb6"
local ICON_BRK = "\xe2\x97\x8f"
local ICON_INSPECT = "\xe2\x97\x89"
local ICON_META = "\xe2\x97\x86"
local ICON_CHEVRON = "\xe2\x9d\xaf"
local ICON_STACK = "\xe2\x89\xa1"

-- a brand header and tagline
local BRAND_TITLE = " " .. ICON_FLOW .. " TURBO DEBUG"
local BRAND_TAGLINE = "   modal text + GUI debugger · left hand keys, right hand mouse"

local function build()
  local lines = { "", BRAND_TITLE, BRAND_TAGLINE, "" }
  local hl = {} -- list of { line_idx, col_start, col_end, hl_group }

  -- title + tagline highlights
  hl[#hl + 1] = { 1, 0, #BRAND_TITLE, "TurboDebugHelpBrand" }
  hl[#hl + 1] = { 2, 0, #BRAND_TAGLINE, "TurboDebugHelpTagline" }

  local function section(icon, title)
    lines[#lines + 1] = "  " .. icon .. "  " .. title
    local idx = #lines - 1
    hl[#hl + 1] = { idx, 2, 2 + #icon, "TurboDebugHelpSectionIcon" }
    hl[#hl + 1] = { idx, 2 + #icon + 2, 2 + #icon + 2 + #title, "TurboDebugHelpSection" }
  end

  local function entry(pre, keyletter, post)
    -- format: "      <pre>(<keyletter>)<tail>"
    -- e.g., "      (s)tep over"  or  "      run to (C) cursor"
    -- the key letter is inside the parens pair
    local indent = "      "
    -- pre already ends at "("; post already starts with ")"
    local line = indent .. pre .. keyletter .. post
    local idx = #lines
    lines[#lines + 1] = line
    -- highlight: the key letter itself
    local col = #indent + #pre
    hl[#hl + 1] = { idx, col, col + #keyletter, "TurboDebugHelpKey" }
    -- highlight the surrounding parens dimmer
    hl[#hl + 1] = { idx, col - 1, col, "TurboDebugHelpParen" }
    hl[#hl + 1] = { idx, col + #keyletter, col + #keyletter + 1, "TurboDebugHelpParen" }
  end

  local function add_modal(list)
    for _, row in ipairs(list) do
      local action, letter, pre, post = row[1], row[2], row[3], row[4]
      local configured = config.opts.keys[action]
      if configured then
        -- if the user remapped, show their actual key (preserves surprise-free behavior)
        local lk = configured
        entry(pre, lk, post)
      end
    end
  end

  local function add_global(list)
    for _, row in ipairs(list) do
      local action, label = row[1], row[2]
      local key = config.opts.global_keys[action]
      if key then
        local indent = "      "
        local line = indent .. string.format("%-13s ", key) .. label
        local idx = #lines
        lines[#lines + 1] = line
        hl[#hl + 1] = { idx, #indent, #indent + #key, "TurboDebugHelpKey" }
      end
    end
  end

  local function add_pane(list)
    for _, row in ipairs(list) do
      local key, label = row[1], row[2]
      local indent = "      "
      local line = indent .. string.format("%-6s ", key) .. label
      local idx = #lines
      lines[#lines + 1] = line
      hl[#hl + 1] = { idx, #indent, #indent + #key, "TurboDebugHelpKey" }
    end
  end

  section(ICON_FLOW, "Flow")
  add_modal(flow)
  lines[#lines + 1] = ""

  section(ICON_BRK, "Breakpoints")
  add_modal(breakpoints)
  lines[#lines + 1] = ""

  section(ICON_INSPECT, "Inspect")
  add_modal(inspect)
  lines[#lines + 1] = ""

  section(ICON_META, "Help")
  add_modal(meta)
  lines[#lines + 1] = ""

  section(ICON_CHEVRON, "Always available")
  add_global(globals)
  lines[#lines + 1] = ""

  section(ICON_STACK, "In dap-ui panes")
  add_pane(dapui_panes)
  lines[#lines + 1] = ""

  local help_key = config.opts.keys.help or "?"
  lines[#lines + 1] = "   press " .. help_key .. " anytime to reopen"
  lines[#lines + 1] = ""

  local width = 0
  for _, l in ipairs(lines) do
    if vim.fn.strdisplaywidth(l) > width then width = vim.fn.strdisplaywidth(l) end
  end
  return lines, width + 2, hl
end

function M.close()
  if win_id and vim.api.nvim_win_is_valid(win_id) then vim.api.nvim_win_close(win_id, true) end
  win_id = nil
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then vim.api.nvim_buf_delete(buf_id, { force = true }) end
  buf_id = nil
end

function M.open()
  M.close()

  local lines, width, hl = build()
  local height = #lines

  buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  local ns = vim.api.nvim_create_namespace("turbo-debug.help")
  for _, span in ipairs(hl) do
    pcall(vim.api.nvim_buf_set_extmark, buf_id, ns, span[1], span[2], {
      end_row = span[1],
      end_col = span[3],
      hl_group = span[4],
    })
  end

  vim.bo[buf_id].modifiable = false
  vim.bo[buf_id].bufhidden = "wipe"

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

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

  vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "CmdlineEnter" }, {
    once = true,
    callback = function() M.close() end,
  })
end

function M.is_open() return win_id ~= nil and vim.api.nvim_win_is_valid(win_id) end

return M
