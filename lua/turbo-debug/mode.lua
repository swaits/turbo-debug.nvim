local config = require("turbo-debug.config")
local help = require("turbo-debug.help")

local M = {}

local active = false
local active_win = nil
local saved_winbar = nil

-- floating control-bar window (independent of lualine)
local bar_win, bar_buf = nil, nil

-- installed[buf][name] = { key = lhs, prev_n = <prev n-mode map>, prev_v = <prev v-mode map> }
local installed = {}

local dapui_initialized = false
local vt_initialized = false

-- ─── icon constants (Nerd Font Codicons, byte-escaped) ───────────────────────
-- All in the PUA range U+EA60..U+EC1E. Encoded as UTF-8 bytes so the source
-- file stays ASCII through any tool pipeline that strips PUA codepoints.

local ICON = {
  -- Control-bar emoji — strictly supplementary-plane (U+1F000+) or
  -- standalone-emoji-default (like 🛑) codepoints. No VS16-dependent
  -- glyphs: those render as text-mode in half of modern terminals, which
  -- is exactly the "some icons are blocks, some are chars" inconsistency
  -- the last iteration had. Every icon here is guaranteed to render as a
  -- colored emoji in Ghostty + any modern terminal with emoji support.
  go         = "\xf0\x9f\x9f\xa2",              -- 🟢 green circle (U+1F7E2) — go / continue / running
  start_rkt  = "\xf0\x9f\x9a\x80",              -- 🚀 rocket (U+1F680) — launch a new session
  step_over  = "\xf0\x9f\x91\xa3",              -- 👣 footprints (U+1F463) — step
  step_into  = "\xf0\x9f\x94\xbd",              -- 🔽 down-pointing red triangle (U+1F53D) — into
  step_out   = "\xf0\x9f\x94\xbc",              -- 🔼 up-pointing red triangle (U+1F53C) — out
  restart    = "\xe2\x99\xbb\xef\xb8\x8f",      -- ♻️ recycle (U+267B + VS16) — user's pick
  stop       = "\xf0\x9f\x9b\x91",              -- 🛑 octagonal stop sign (U+1F6D1)

  -- pane-title emoji (supplementary plane — reliably colorful)
  scopes      = "\xf0\x9f\x94\x8e",             -- 🔎 magnifier (U+1F50E)
  watches     = "\xf0\x9f\x91\x81\xef\xb8\x8f", -- 👁️ eye (U+1F441 + VS16)
  stacks      = "\xf0\x9f\x93\x9a",             -- 📚 books (U+1F4DA)
  breakpoints = "\xf0\x9f\x94\xb4",             -- 🔴 red circle (U+1F534)
  terminal    = "\xf0\x9f\x92\xbb",             -- 💻 laptop (U+1F4BB)
  repl        = "\xf0\x9f\x92\xac",             -- 💬 speech balloon (U+1F4AC)

  -- brand / state emoji
  bug         = "\xf0\x9f\x90\x9b",             -- 🐛 bug (U+1F41B)
  help        = "\xf0\x9f\x92\xa1",             -- 💡 lightbulb (U+1F4A1) — insight/help

  -- IP arrows
  ip_left     = "\xf0\x9f\x91\x88",             -- 👈 backhand pointing left (U+1F448)

  -- misc
  divider     = "\xc2\xb7",                     -- · middle dot
  ellipsis    = "\xe2\x80\xa6",                 -- … horizontal ellipsis
  wrap_mark   = "\xe2\x86\xb3",                 -- ↳ downward arrow w/ tip right
  hline       = "\xe2\x94\x80",                 -- ─ light horizontal
}

-- ─── layout ──────────────────────────────────────────────────────────────────

local function build_default_layouts()
  local pos = config.opts.sidebar == "right" and "right" or "left"
  return {
    {
      position = pos,
      size = 40,
      -- Order is deliberate:
      --   1. Call Stack — answers "where am I?" first when paused
      --   2. Scopes     — "what's the state here?" (updates when you click a
      --                    frame above, so adjacency is ergonomic)
      --   3. Watches    — user-curated expressions, less frequently consulted
      --   4. Breakpoints — maintenance view, accessed rarely during a pause
      elements = {
        { id = "stacks",      size = 0.25 },
        { id = "scopes",      size = 0.40 },
        { id = "watches",     size = 0.20 },
        { id = "breakpoints", size = 0.15 },
      },
    },
    {
      -- 9 rows (was 12) to leave room for the 3-row control bar below
      position = "bottom",
      size = 9,
      elements = {
        { id = "repl",    size = 0.50 },
        { id = "console", size = 0.50 },
      },
    },
  }
end

-- ─── highlights ──────────────────────────────────────────────────────────────

local function define_highlights()
  local hl = vim.api.nvim_set_hl
  hl(0, "TurboDebugBorderActive",   { default = true, link = "Function" })
  hl(0, "TurboDebugBorderInactive", { default = true, link = "Comment" })
  hl(0, "TurboDebugWinbar",         { default = true, link = "DiagnosticError" })
  hl(0, "TurboDebugBar",            { default = true, link = "StatusLine" })
  hl(0, "TurboDebugBarSeparator",   { default = true, link = "FloatBorder" })
  hl(0, "TurboDebugBarCtrl",        { default = true, link = "StatusLine" })
  hl(0, "TurboDebugBarStatus",      { default = true, link = "Comment" })
  hl(0, "TurboDebugBarReady",       { default = true, link = "DiagnosticHint" })
  hl(0, "TurboDebugBarRunning",     { default = true, link = "DiagnosticInfo" })
  hl(0, "TurboDebugBarPaused",      { default = true, link = "DiagnosticError" })

  -- The key letter inside (c)ontinue etc. gets bold + underline + Special's
  -- fg. nvim_set_hl can't combine link + bold, so we copy Special's fg
  -- explicitly and add bold/underline. Re-applied on ColorScheme so theme
  -- swaps don't blank it out.
  local function apply_key_hl()
    local ok, src = pcall(vim.api.nvim_get_hl, 0, { name = "Special", link = false })
    if not ok or not src or not src.fg then
      -- fallback: at least make it bold via linking to something bold-ish
      vim.api.nvim_set_hl(0, "TurboDebugBarKey", { default = true, link = "Special" })
      return
    end
    vim.api.nvim_set_hl(0, "TurboDebugBarKey", {
      fg = src.fg, bg = src.bg, bold = true, underline = true, default = true,
    })
  end
  apply_key_hl()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("TurboDebugBarKeyHL", { clear = true }),
    callback = apply_key_hl,
  })
end

local function setup_active_win_highlights()
  local active_hl = "WinSeparator:TurboDebugBorderActive,FloatBorder:TurboDebugBorderActive"
  local inactive_hl = "WinSeparator:TurboDebugBorderInactive,FloatBorder:TurboDebugBorderInactive"

  local group = vim.api.nvim_create_augroup("TurboDebugActiveWin", { clear = true })
  local function apply(win, hl)
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
      local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype or ""
      if ft:match("^dapui_") or ft == "dap-repl" then
        vim.wo[win].winhighlight = hl
      end
    end
  end
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function() apply(vim.api.nvim_get_current_win(), active_hl) end,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function() apply(vim.api.nvim_get_current_win(), inactive_hl) end,
  })
end

-- ─── control bar (buffer-rendered, not winbar — survives floating windows) ──

-- Layout: a 2-row floating window pinned above the statusline.
--   Row 0: a full-width ─ separator line (distinguishes bar from REPL/Console).
--   Row 1: state chip + clickable control buttons + dap status + cursor pos.
-- Content is written to the buffer directly (winbar doesn't render reliably
-- in minimal-style floats). Highlights via extmarks. Clicks via a buffer-local
-- <LeftMouse> keymap that inspects cursor column and dispatches.

local bar_ns = vim.api.nvim_create_namespace("turbo-debug.bar")

-- `click_zones` is populated by render_bar: each entry is { col_start, col_end, fn }.
-- On <LeftMouse> in the bar, we look up the cursor column and fire the matching fn.
local click_zones = {}

local function dap_state()
  local ok, dap = pcall(require, "dap")
  if not ok then return "READY", "TurboDebugBarReady" end
  local s = dap.session()
  if not s then return "READY", "TurboDebugBarReady" end
  if s.stopped_thread_id then return "PAUSED", "TurboDebugBarPaused" end
  return "RUNNING", "TurboDebugBarRunning"
end

local function action(name)
  return function() local a = M.actions(); if a[name] then a[name]() end end
end

local function keyof(name, fallback)
  local k = config.opts.keys[name]
  if type(k) == "string" then return k end
  return fallback
end

-- Build a label's byte-level representation: returns { text, hl_spans, key_col, key_end_col }
-- Format: "<icon> (<key>)<tail>"  e.g.  ` (c)ontinue` with byte offsets for highlights.
local function build_control_text(icon, key, tail)
  local parts = {}
  local function add(s) parts[#parts + 1] = s end
  local function col() return #table.concat(parts) end

  add(icon); add(" ")
  add("(")
  local key_col = col()
  add(key)
  local key_end_col = col()
  add(")")
  add(tail or "")

  return table.concat(parts), key_col, key_end_col
end

local function render_bar()
  if not (bar_buf and vim.api.nvim_buf_is_valid(bar_buf)) then return end
  if not (bar_win and vim.api.nvim_win_is_valid(bar_win)) then return end

  local width = vim.api.nvim_win_get_width(bar_win)
  if width < 1 then width = vim.o.columns end
  local sep = string.rep(ICON.hline, width)

  local state, state_hl = dap_state()

  -- ─── LEFT ZONE ─── state chip (always shown) + dap.status() (optional)
  local chip_text = " " .. ICON.bug .. " DEBUG " .. ICON.divider .. " " .. state .. " "
  local status_ok, status_msg = pcall(function() return require("dap").status() end)
  if not status_ok then status_msg = "" end
  local status_text = (status_msg ~= "" and ("  " .. status_msg) or "")

  -- ─── CENTER ZONE ─── control labels, each clickable. Two labels have
  -- modal variants that track the dap state so the text reflects what the
  -- key will ACTUALLY do right now:
  --   (c) start    when no session is running
  --   (c)ontinue   when a session is paused or running
  --   (q)uit       when no session is running (exits debug mode)
  --   (q) terminate when a session is running (kills the process)
  local has_session = state ~= "READY"
  local continue_icon, continue_tail
  if has_session then
    continue_icon = ICON.go
    continue_tail = "ontinue"
  else
    continue_icon = ICON.start_rkt
    continue_tail = " start"
  end
  local quit_tail = has_session and " terminate" or "uit"

  local controls = {
    { icon = continue_icon,  key = keyof("continue",  "c"), tail = continue_tail, fn = action("continue")  },
    { icon = ICON.step_over, key = keyof("step_over", "s"), tail = "tep",         fn = action("step_over") },
    { icon = ICON.step_into, key = keyof("step_into", "d"), tail = "escend",      fn = action("step_into") },
    { icon = ICON.step_out,  key = keyof("step_out",  "r"), tail = "eturn",       fn = action("step_out")  },
    { icon = ICON.restart,   key = keyof("restart",   "R"), tail = "estart",      fn = action("restart")   },
    { icon = ICON.stop,      key = keyof("terminate", "q"), tail = quit_tail,     fn = action("terminate") },
  }

  -- ─── RIGHT ZONE ─── help (no "(?)" — the ❓ emoji is self-documenting)
  local help_icon = ICON.help
  local help_label_text = help_icon .. " help "
  local help_fn = function() require("turbo-debug.help").open() end

  -- compose the center text first so we can measure it
  local center_parts = {}
  local center_spans = {}      -- { byte_start, byte_end, hl }
  local center_key_spans = {}  -- { byte_start, byte_end } for TurboDebugBarKey
  local center_zones = {}      -- { byte_start, byte_end, fn } pre-display-column
  local gap = "   "
  for i, c in ipairs(controls) do
    local prefix_len = #table.concat(center_parts)
    if i > 1 then
      center_parts[#center_parts + 1] = gap
      prefix_len = prefix_len + #gap
    end
    local txt, kcol, kend = build_control_text(c.icon, c.key, c.tail)
    local label_start = prefix_len
    local label_end = prefix_len + #txt
    center_parts[#center_parts + 1] = txt
    center_spans[#center_spans + 1] = { label_start, label_end, "TurboDebugBarCtrl" }
    center_key_spans[#center_key_spans + 1] = { label_start + kcol, label_start + kend }
    center_zones[#center_zones + 1] = { label_start, label_end, c.fn }
  end
  local center_text = table.concat(center_parts)

  -- widths in display columns (not bytes — emoji are multi-byte and multi-cell)
  local left_dw   = vim.fn.strdisplaywidth(chip_text) + vim.fn.strdisplaywidth(status_text)
  local center_dw = vim.fn.strdisplaywidth(center_text)
  local right_dw  = vim.fn.strdisplaywidth(help_label_text)

  -- Graceful degradation when the window narrows. Priority (most important last):
  --   1. dap.status()     — drop first
  --   2. center controls  — truncate from the right
  --   3. state chip       — collapse to just "🐛"
  --   4. help             — NEVER drop
  local show_status = true
  local show_controls = true
  local show_chip = true

  if left_dw + center_dw + right_dw + 4 > width then
    show_status = false  -- drop status first
    left_dw = vim.fn.strdisplaywidth(chip_text)
  end
  if left_dw + center_dw + right_dw + 4 > width then
    show_controls = false  -- drop center next
    center_dw = 0
  end
  if left_dw + right_dw + 2 > width then
    show_chip = false  -- collapse chip to just the bug icon
    chip_text = " " .. ICON.bug .. " "
    left_dw = vim.fn.strdisplaywidth(chip_text)
  end

  -- compose: [left][pad1][center][pad2][right]
  local left_text = chip_text .. (show_status and status_text or "")
  local right_text = help_label_text
  local center_to_use = show_controls and center_text or ""
  local center_dw_used = show_controls and center_dw or 0

  local remain = width - left_dw - center_dw_used - right_dw
  if remain < 0 then remain = 0 end
  -- split remaining space symmetrically on either side of the center
  local pad1 = math.floor(remain / 2)
  local pad2 = remain - pad1
  local line = left_text .. string.rep(" ", pad1) .. center_to_use .. string.rep(" ", pad2) .. right_text

  -- safety truncate
  if vim.fn.strdisplaywidth(line) > width then
    -- keep right-anchored help visible by truncating from the middle if possible
    line = line:sub(1, width)
  end

  vim.bo[bar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(bar_buf, 0, -1, false, { sep, line, sep })
  vim.bo[bar_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(bar_buf, bar_ns, 0, -1)

  -- top + bottom separator highlights
  vim.api.nvim_buf_set_extmark(bar_buf, bar_ns, 0, 0, {
    end_row = 0, end_col = #sep, hl_group = "TurboDebugBarSeparator",
  })
  vim.api.nvim_buf_set_extmark(bar_buf, bar_ns, 2, 0, {
    end_row = 2, end_col = #sep, hl_group = "TurboDebugBarSeparator",
  })

  -- state chip highlight (at the start of the line)
  local chip_end = #chip_text
  pcall(vim.api.nvim_buf_set_extmark, bar_buf, bar_ns, 1, 0, {
    end_row = 1, end_col = chip_end, hl_group = state_hl,
  })
  if show_status and #status_text > 0 then
    local s = chip_end
    local e = chip_end + #status_text
    pcall(vim.api.nvim_buf_set_extmark, bar_buf, bar_ns, 1, s, {
      end_row = 1, end_col = e, hl_group = "TurboDebugBarStatus",
    })
  end

  -- center highlights (offset by left_text + pad1 bytes)
  local center_byte_offset = #left_text + pad1
  click_zones = {}
  if show_controls then
    for _, span in ipairs(center_spans) do
      pcall(vim.api.nvim_buf_set_extmark, bar_buf, bar_ns, 1, center_byte_offset + span[1], {
        end_row = 1, end_col = center_byte_offset + span[2], hl_group = span[3],
      })
    end
    for _, span in ipairs(center_key_spans) do
      pcall(vim.api.nvim_buf_set_extmark, bar_buf, bar_ns, 1, center_byte_offset + span[1], {
        end_row = 1, end_col = center_byte_offset + span[2], hl_group = "TurboDebugBarKey",
      })
    end
    for _, zone in ipairs(center_zones) do
      local byte_start = center_byte_offset + zone[1]
      local byte_end = center_byte_offset + zone[2]
      local dcol_start = vim.fn.strdisplaywidth(line:sub(1, byte_start))
      local dcol_end   = vim.fn.strdisplaywidth(line:sub(1, byte_end))
      click_zones[#click_zones + 1] = { dcol_start, dcol_end, zone[3] }
    end
  end

  -- right zone (help) highlight + click
  local right_byte_start = #line - #right_text
  pcall(vim.api.nvim_buf_set_extmark, bar_buf, bar_ns, 1, right_byte_start, {
    end_row = 1, end_col = #line, hl_group = "TurboDebugBarCtrl",
  })
  -- emphasize the ❓ itself with the key-hint color
  pcall(vim.api.nvim_buf_set_extmark, bar_buf, bar_ns, 1, right_byte_start + 1, {
    end_row = 1, end_col = right_byte_start + 1 + #ICON.help, hl_group = "TurboDebugBarKey",
  })
  local help_dcol_start = vim.fn.strdisplaywidth(line:sub(1, right_byte_start))
  local help_dcol_end   = vim.fn.strdisplaywidth(line)
  click_zones[#click_zones + 1] = { help_dcol_start, help_dcol_end, help_fn }
end

local function bar_position()
  -- 3 rows (─ top, content, ─ bottom). Sits above the statusline.
  local row
  if vim.o.laststatus > 0 then
    row = vim.o.lines - vim.o.cmdheight - 4  -- 3 (bar) + 1 (statusline)
  else
    row = vim.o.lines - vim.o.cmdheight - 3  -- 3 (bar)
  end
  if row < 0 then row = 0 end
  return {
    relative  = "editor",
    row       = row,
    col       = 0,
    width     = vim.o.columns,
    height    = 3,
    style     = "minimal",
    border    = "none",
    focusable = false,
    noautocmd = true,
    zindex    = 50,
  }
end

local function handle_bar_click()
  local pos = vim.fn.getmousepos()
  if not pos or pos.winid ~= bar_win then return end
  -- only the middle (content) row is clickable; top/bottom are separators
  if pos.line ~= 2 then return end
  local col = pos.wincol - 1
  for _, zone in ipairs(click_zones) do
    if col >= zone[1] and col < zone[2] then
      zone[3]()
      return
    end
  end
end

local function open_bar()
  if bar_win and vim.api.nvim_win_is_valid(bar_win) then
    render_bar()
    return
  end
  bar_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[bar_buf].bufhidden = "wipe"
  vim.bo[bar_buf].buftype = "nofile"
  vim.bo[bar_buf].swapfile = false
  vim.bo[bar_buf].buflisted = false
  vim.bo[bar_buf].filetype = "TurboDebugBar"
  bar_win = vim.api.nvim_open_win(bar_buf, false, bar_position())
  vim.wo[bar_win].winhighlight = "Normal:TurboDebugBar,EndOfBuffer:TurboDebugBar"
  vim.wo[bar_win].winfixheight = true
  vim.wo[bar_win].list = false
  vim.wo[bar_win].cursorline = false
  vim.wo[bar_win].number = false
  vim.wo[bar_win].relativenumber = false
  vim.wo[bar_win].signcolumn = "no"
  vim.wo[bar_win].statuscolumn = ""
  vim.wo[bar_win].wrap = false

  -- click dispatch
  vim.keymap.set("n", "<LeftMouse>", handle_bar_click, { buffer = bar_buf, silent = true, nowait = true })
  vim.keymap.set("n", "<LeftRelease>", "<Nop>", { buffer = bar_buf, silent = true, nowait = true })

  -- Safety net: if the user somehow lands in the bar buffer (mouse drag into
  -- it, or some focus accident), bounce them back out immediately. Stops
  -- them from hitting E21 "Cannot make changes, 'modifiable' is off" when
  -- they try to type in a non-modifiable buffer.
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = bar_buf,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_get_current_buf() == bar_buf then
          pcall(vim.cmd, "wincmd p")
        end
      end)
    end,
  })

  render_bar()
end

local function close_bar()
  if bar_win and vim.api.nvim_win_is_valid(bar_win) then
    pcall(vim.api.nvim_win_close, bar_win, true)
  end
  bar_win, bar_buf = nil, nil
  click_zones = {}
end

local function reposition_bar()
  if bar_win and vim.api.nvim_win_is_valid(bar_win) then
    pcall(vim.api.nvim_win_set_config, bar_win, bar_position())
    render_bar()
  end
end

-- ─── dap-ui setup ────────────────────────────────────────────────────────────

local function set_dapui_window_opts(win)
  -- Wrap long values inside the pane so register dumps etc. don't bleed into
  -- adjacent windows. breakindent + showbreak make continuation lines visually
  -- attached to their parent. The `format_value` wrap below truncates only
  -- pathologically-long values.
  --
  -- Also kill line numbers, the statuscolumn (which snacks overrides with a
  -- rendered gutter), and the `~` end-of-buffer markers — these are pure
  -- noise in debug-info panes where there's no file to navigate.
  if vim.api.nvim_win_is_valid(win) then
    vim.wo[win].wrap           = true
    vim.wo[win].breakindent    = true
    vim.wo[win].linebreak      = true
    vim.wo[win].showbreak      = " " .. ICON.wrap_mark .. " "
    vim.wo[win].sidescrolloff  = 0
    vim.wo[win].cursorline     = true
    vim.wo[win].number         = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn     = "no"
    vim.wo[win].statuscolumn   = ""
    vim.wo[win].foldcolumn     = "0"
    -- make end-of-buffer `~` invisible by setting EOB fillchar to space
    vim.wo[win].fillchars      = "eob: "
  end
end

local function patch_format_value()
  local ok, util = pcall(require, "dapui.util")
  if not ok or not util or type(util.format_value) ~= "function" then return end
  if util._turbo_debug_wrapped then return end
  local orig = util.format_value
  util.format_value = function(value_start, value)
    if type(value) ~= "string" then return orig(value_start, value) end
    local cap = config.opts.max_value_width or 2000
    if cap <= 0 or #value <= cap then return orig(value_start, value) end
    return orig(value_start, value:sub(1, cap - 1) .. ICON.ellipsis)
  end
  util._turbo_debug_wrapped = true
end

local redraw_pending = false
local function schedule_console_redraw()
  if redraw_pending then return end
  redraw_pending = true
  vim.defer_fn(function()
    redraw_pending = false
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "dapui_console" then
        for _, win in ipairs(vim.fn.win_findbuf(buf)) do
          if vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_call, win, function() vim.cmd("redraw!") end)
          end
        end
      end
    end
  end, config.opts.console_refresh_ms or 50)
end

local function ensure_dapui()
  if dapui_initialized then return end
  dapui_initialized = true
  local dapui_opts = vim.deepcopy(config.opts.dapui)
  if not dapui_opts.layouts then dapui_opts.layouts = build_default_layouts() end
  require("dapui").setup(dapui_opts)
  patch_format_value()

  local dap = require("dap")
  dap.listeners.after.event_initialized["turbo-debug"] = function()
    require("dapui").open()
  end

  -- K = hover during a live dap session (global, not per-buffer)
  dap.listeners.after.event_initialized["turbo-debug-hover"] = function()
    vim.keymap.set("n", "K", function()
      require("dap.ui.widgets").hover(nil, { border = "rounded" })
    end, { silent = true, desc = "DAP hover" })
  end
  dap.listeners.after.event_terminated["turbo-debug-hover"] = function()
    pcall(vim.keymap.del, "n", "K")
  end

  -- console refresh: trailing-edge throttled so chatty programs don't DOS us
  dap.listeners.after.event_output["turbo-debug-redraw"] = schedule_console_redraw

  -- IP marker: paired arrows. Gutter sign 👉 + EOL vtext 👈 REASON flanking
  -- the paused line. clear_ip() wipes both our own extmarks AND nvim-dap's
  -- DapStopped gutter signs, so a restart (or a natural session end) doesn't
  -- leave a stale 👉 behind on the last-paused line.
  local ip_ns = vim.api.nvim_create_namespace("turbo-debug.ip")
  local function clear_ip()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, ip_ns, 0, -1)
        -- unplace any lingering DapStopped signs (nvim-dap doesn't always
        -- clear these on restart — it's the exact bug the user hit).
        local ok, placed = pcall(vim.fn.sign_getplaced, buf, { group = "*" })
        if ok and placed and placed[1] then
          for _, s in ipairs(placed[1].signs or {}) do
            if s.name == "DapStopped" then
              pcall(vim.fn.sign_unplace, s.group or "", { buffer = buf, id = s.id })
            end
          end
        end
      end
    end
  end

  -- re-render the control bar on any dap state change so the READY/RUNNING/
  -- PAUSED chip and dap.status() text stay live.
  local function refresh_bar() vim.schedule(render_bar) end
  dap.listeners.after.event_initialized["turbo-debug-bar"]  = refresh_bar
  dap.listeners.after.event_stopped["turbo-debug-bar"]      = refresh_bar
  dap.listeners.after.event_continued["turbo-debug-bar"]    = refresh_bar
  dap.listeners.after.event_terminated["turbo-debug-bar"]   = refresh_bar
  dap.listeners.after.event_exited["turbo-debug-bar"]       = refresh_bar

  dap.listeners.after.event_stopped["turbo-debug-ip"] = function(session, body)
    vim.defer_fn(function()
      clear_ip()
      local frame = session and session.current_frame
      if not (frame and frame.source and frame.source.path) then return end
      local buf = vim.fn.bufnr(frame.source.path)
      if buf == -1 or not vim.api.nvim_buf_is_valid(buf) then return end
      local line = math.max(0, (frame.line or 1) - 1)
      local reason = ((body and body.reason) or "stopped"):upper()
      pcall(vim.api.nvim_buf_set_extmark, buf, ip_ns, line, 0, {
        virt_text = {
          { "  " .. ICON.ip_left .. "  ", "DapStopped" },
          { reason,                       "TurboDebugIPReason" },
        },
        virt_text_pos = "eol",
        hl_mode = "combine",
        priority = 200,
      })
    end, 50)
  end
  dap.listeners.after.event_continued["turbo-debug-ip"]  = function() clear_ip() end
  dap.listeners.before.event_terminated["turbo-debug-ip"] = function() clear_ip() end
  dap.listeners.before.event_exited["turbo-debug-ip"]     = function() clear_ip() end

  -- winbar titles on dapui panes — colorful emoji for instant pane recognition
  local titles = {
    dapui_scopes      = " " .. ICON.scopes      .. "  Scopes",
    dapui_watches     = " " .. ICON.watches     .. "  Watches",
    dapui_stacks      = " " .. ICON.stacks      .. "  Call Stack",
    dapui_breakpoints = " " .. ICON.breakpoints .. "  Breakpoints",
    dapui_console     = " " .. ICON.terminal    .. "  Console",
    ["dap-repl"]      = " " .. ICON.repl        .. "  REPL",
  }
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "dapui_*", "dap-repl" },
    callback = function(args)
      -- install keys synchronously (don't defer) so they're ready the moment
      -- the buffer is usable. dapui's own `apply_mapping` pass only touches
      -- <CR>/o/d/e/r/t; we don't conflict except on d and r which we skip.
      if active then M._install_for_buf(args.buf) end
      local ft = vim.bo[args.buf].filetype
      local title = titles[ft]
      vim.schedule(function()
        local win = vim.fn.bufwinid(args.buf)
        if win ~= -1 then
          if title then vim.wo[win].winbar = title end
          set_dapui_window_opts(win)
        end
      end)
    end,
  })

  if config.opts.active_window_highlight then setup_active_win_highlights() end
end

local function ensure_vt()
  if vt_initialized then return end
  vt_initialized = true
  require("nvim-dap-virtual-text").setup(config.opts.virtual_text)
end

-- ─── actions ────────────────────────────────────────────────────────────────

local actions_cache
local visual_actions = { watch = true, hover = true }

local function has_any_breakpoint()
  local ok, bps = pcall(require, "dap.breakpoints")
  if not ok then return false end
  local all = bps.get()
  for _, lines in pairs(all or {}) do
    if #lines > 0 then return true end
  end
  return false
end

-- Find a source window (non-dapui, non-repl, non-bar). nvim-dap reads the
-- current buffer's filetype to pick a launch configuration, so when the user
-- presses `c` while focused in a dapui pane (filetype=dapui_scopes, etc.),
-- we need to temporarily borrow a source window's context.
local function source_window()
  -- prefer the current window if it's a source
  local cur = vim.api.nvim_get_current_win()
  local function is_source(w)
    if not vim.api.nvim_win_is_valid(w) then return false end
    if vim.api.nvim_win_get_config(w).relative ~= "" then return false end
    local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype or ""
    return ft ~= ""
      and not ft:match("^dapui_")
      and ft ~= "dap-repl"
      and ft ~= "TurboDebugBar"
  end
  if is_source(cur) then return cur end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if is_source(w) then return w end
  end
  return nil
end

local function run_in_source(fn)
  -- We can't use nvim_win_call here: dap.continue() may open a vim.ui.select
  -- picker asynchronously, and by the time the picker opens, nvim_win_call
  -- has already returned focus to the original window — the picker opens
  -- but nothing has focus on it, forcing the user to click in to interact.
  -- Actually shift focus to the source window so the picker takes focus
  -- properly.
  local w = source_window()
  if w and w ~= vim.api.nvim_get_current_win() then
    pcall(vim.api.nvim_set_current_win, w)
  end
  return fn()
end

local function launch_with_stop_on_entry()
  local dap = require("dap")
  local ft = vim.bo.filetype or ""
  local cfgs = dap.configurations[ft]
  if not (cfgs and cfgs[1]) then
    dap.continue()
    return
  end
  local cfg = vim.deepcopy(cfgs[1])
  cfg.stopOnEntry = true
  cfg.name = (cfg.name or "debug") .. " (stop on entry)"
  dap.run(cfg)
end

local function smart_continue()
  local dap = require("dap")
  if dap.session() then dap.continue(); return end
  run_in_source(function()
    if config.opts.stop_on_entry_when_no_breakpoints ~= false and not has_any_breakpoint() then
      launch_with_stop_on_entry()
    else
      dap.continue()
    end
  end)
end

local function step_or_launch(step_fn)
  if require("dap").session() then
    step_fn()
  else
    smart_continue()
  end
end

local function smart_terminate()
  -- q is context-aware: if a session is running, kill it and stay in debug
  -- mode so the user can read the console / post-mortem. If no session is
  -- running, q exits debug mode entirely.
  local dap = require("dap")
  if dap.session() then
    pcall(dap.terminate)
  else
    M.exit()
  end
end

local function setup_actions()
  if actions_cache then return actions_cache end
  local dap = require("dap")
  local pb = require("persistent-breakpoints.api")

  actions_cache = {
    continue      = smart_continue,
    step_over     = function() step_or_launch(dap.step_over) end,
    step_into     = function() step_or_launch(dap.step_into) end,
    step_out      = function() step_or_launch(dap.step_out) end,
    run_to_cursor = function() dap.run_to_cursor() end,
    restart       = function() dap.restart() end,
    terminate     = smart_terminate,
    help = function()
      if help.is_open() then help.close() else help.open() end
    end,
    breakpoint        = function() pb.toggle_breakpoint() end,
    cond_breakpoint   = function() pb.set_conditional_breakpoint() end,
    clear_breakpoints = function() pb.clear_all_breakpoints() end,
    watch = function()
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
    end,
    hover = function() require("dapui").eval() end,
    eval  = function() require("dapui").float_element("repl") end,
  }
  return actions_cache
end

function M.actions() return actions_cache or setup_actions() end

-- ─── keymap install / clear ─────────────────────────────────────────────────

local function find_buf_mapping(buf, lhs, mode)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhs == lhs then return m end
  end
  return nil
end

local function restore_mapping(buf, mode, map)
  local rhs = map.rhs or map.callback
  if not rhs then return end
  pcall(vim.keymap.set, mode, map.lhs, rhs, {
    buffer = buf,
    silent = map.silent == 1,
    noremap = map.noremap == 1,
    expr = map.expr == 1,
    desc = map.desc,
  })
end

function M._install_for_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  -- Skip the control-bar buffer entirely — its own <LeftMouse> keymap handles
  -- button clicks, and debug keys like `c` would fire accidentally on click.
  if vim.bo[buf].filetype == "TurboDebugBar" then return end

  local acts = setup_actions()
  local ft = vim.bo[buf].filetype or ""
  local is_dapui = ft:match("^dapui_") or ft == "dap-repl"
  installed[buf] = installed[buf] or {}
  for name, key in pairs(config.opts.keys) do
    if key and acts[name] then
      -- yield d/r to dapui's native remove/repl inside its own panes
      if not (is_dapui and (name == "step_into" or name == "step_out")) then
        -- Only record prev-mapping on first install; subsequent installs
        -- (force-reinstall on focus change) keep the original stash so
        -- exit-time restoration still works.
        local entry = installed[buf][name]
        if not entry then
          local prev_n = find_buf_mapping(buf, key, "n")
          local prev_v = visual_actions[name] and find_buf_mapping(buf, key, "v") or nil
          entry = { key = key, prev_n = prev_n, prev_v = prev_v }
          installed[buf][name] = entry
        end
        local opts = { buffer = buf, silent = true, nowait = true, desc = "turbo-debug: " .. name }
        pcall(vim.keymap.set, "n", key, acts[name], opts)
        if visual_actions[name] then
          pcall(vim.keymap.set, "v", key, acts[name], opts)
        end
      end
    end
  end
end

local function clear_all_modal_keys()
  for buf, entries in pairs(installed) do
    if vim.api.nvim_buf_is_valid(buf) then
      for name, entry in pairs(entries) do
        pcall(vim.keymap.del, "n", entry.key, { buffer = buf })
        if visual_actions[name] then
          pcall(vim.keymap.del, "v", entry.key, { buffer = buf })
        end
        if entry.prev_n then restore_mapping(buf, "n", entry.prev_n) end
        if entry.prev_v then restore_mapping(buf, "v", entry.prev_v) end
      end
    end
  end
  installed = {}
end

-- ─── source-window debug chrome ─────────────────────────────────────────────

local function set_debug_chrome()
  active_win = vim.api.nvim_get_current_win()
  saved_winbar = vim.wo[active_win].winbar
  vim.wo[active_win].winbar = "%#TurboDebugWinbar# " .. ICON.bug .. " DEBUG %* " .. ICON.divider .. " %f"
end

local function clear_debug_chrome()
  if active_win and vim.api.nvim_win_is_valid(active_win) then
    vim.wo[active_win].winbar = saved_winbar or ""
  end
  active_win = nil
  saved_winbar = nil
end

-- ─── public API ─────────────────────────────────────────────────────────────

function M.enter()
  if active then return end
  active = true
  define_highlights()
  setup_actions()

  local group = vim.api.nvim_create_augroup("TurboDebugModalKeys", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      if active then M._install_for_buf(args.buf) end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = reposition_bar,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M._install_for_buf(buf) end
  end

  set_debug_chrome()
  ensure_dapui()
  require("dapui").open()
  open_bar()

  -- second install pass after dapui has created its buffers
  vim.schedule(function()
    if not active then return end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then M._install_for_buf(buf) end
    end
    reposition_bar()
  end)

  ensure_vt()
  require("nvim-dap-virtual-text").enable()

  if config.opts.help_on_enter then help.open() end
end

function M.exit()
  if not active then return end
  active = false

  if require("dap").session() then pcall(require("dap").terminate) end

  pcall(vim.api.nvim_del_augroup_by_name, "TurboDebugModalKeys")
  clear_all_modal_keys()
  clear_debug_chrome()
  close_bar()
  help.close()

  if dapui_initialized then require("dapui").close() end
  if vt_initialized then require("nvim-dap-virtual-text").disable() end
end

function M.toggle()
  if active then M.exit() else M.enter() end
end

function M.is_active() return active end

return M
