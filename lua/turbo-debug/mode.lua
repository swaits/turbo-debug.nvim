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
  -- control-bar buttons (colorful emoji for instant recognition)
  play        = "\xe2\x96\xb6\xef\xb8\x8f",     -- ▶️ (U+25B6 + VS16)
  step_over   = "\xe2\x8f\xad\xef\xb8\x8f",     -- ⏭️ next track (U+23ED + VS16)
  step_into   = "\xe2\xac\x87\xef\xb8\x8f",     -- ⬇️ downwards arrow (U+2B07 + VS16)
  step_out    = "\xe2\xac\x86\xef\xb8\x8f",     -- ⬆️ upwards arrow (U+2B06 + VS16)
  restart     = "\xf0\x9f\x94\x84",             -- 🔄 counterclockwise arrows (U+1F504)
  stop        = "\xf0\x9f\x9b\x91",             -- 🛑 octagonal sign (U+1F6D1)
  close       = "\xe2\x9d\x8c",                 -- ❌ cross mark (U+274C)

  -- pane-title emoji
  scopes      = "\xf0\x9f\x94\x8e",             -- 🔎 magnifier right (U+1F50E)
  watches     = "\xf0\x9f\x91\x81\xef\xb8\x8f", -- 👁️ eye (U+1F441 + VS16)
  stacks      = "\xf0\x9f\x93\x9a",             -- 📚 books (U+1F4DA)
  breakpoints = "\xf0\x9f\x94\xb4",             -- 🔴 red circle (U+1F534) — matches BP sign
  terminal    = "\xf0\x9f\x92\xbb",             -- 💻 laptop (U+1F4BB)
  repl        = "\xf0\x9f\x92\xac",             -- 💬 speech balloon (U+1F4AC)

  -- debug badge
  bug         = "\xf0\x9f\x90\x9b",             -- 🐛 bug (U+1F41B)

  -- IP arrows
  ip_left     = "\xf0\x9f\x91\x88",             -- 👈 backhand index pointing left (U+1F448)

  -- misc
  divider     = "\xc2\xb7",                     -- · middle dot
  ellipsis    = "\xe2\x80\xa6",                 -- … horizontal ellipsis
  wrap_mark   = "\xe2\x86\xb3",                 -- ↳ downward arrow w/ tip right
  hline       = "\xe2\x94\x80",                 -- ─ box drawings light horizontal
}

-- ─── layout ──────────────────────────────────────────────────────────────────

local function build_default_layouts()
  local pos = config.opts.sidebar == "right" and "right" or "left"
  return {
    {
      position = pos,
      size = 40,
      elements = {
        { id = "scopes",      size = 0.40 },
        { id = "watches",     size = 0.20 },
        { id = "stacks",      size = 0.25 },
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
  hl(0, "TurboDebugBarKey",         { default = true, link = "Special" })
  hl(0, "TurboDebugBarStatus",      { default = true, link = "Comment" })
  hl(0, "TurboDebugBarReady",       { default = true, link = "DiagnosticHint" })
  hl(0, "TurboDebugBarRunning",     { default = true, link = "DiagnosticInfo" })
  hl(0, "TurboDebugBarPaused",      { default = true, link = "DiagnosticError" })
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

-- Helper to look up a configured modal key letter. Falls back to the given
-- default so the bar never blanks out if the user remapped something.
local function keyof(name, fallback)
  local k = config.opts.keys[name]
  if type(k) == "string" then return k end
  return fallback
end

-- Build one control label: returns { segments = { {text, hl, key_span=?}, ... }, fn = action-fn }
-- The label looks like "▶️ (c)ontinue" — the whole text is one click zone;
-- the parenthesized key letter gets a distinct TurboDebugBarKey highlight.
local function build_label(icon, key, word_head, word_tail, fn)
  -- layout: "<icon> (<key>)<word_tail>"  e.g. "▶️ (c)ontinue"
  -- but to match the mnemonic style from help: "(c)ontinue" etc.
  -- word_head + "(" + key + ")" + word_tail  allows things like  "run to (C) cursor"
  return {
    icon = icon,
    key  = key,
    head = word_head or "",
    tail = word_tail or "",
    fn   = fn,
  }
end

local function render_bar()
  if not (bar_buf and vim.api.nvim_buf_is_valid(bar_buf)) then return end
  if not (bar_win and vim.api.nvim_win_is_valid(bar_win)) then return end

  local width = vim.api.nvim_win_get_width(bar_win)
  if width < 1 then width = vim.o.columns end
  local sep = string.rep(ICON.hline, width)

  local state, state_hl = dap_state()

  -- State chip: e.g. " 🐛 DEBUG · PAUSED "
  local chip = " " .. ICON.bug .. " DEBUG " .. ICON.divider .. " " .. state .. " "

  -- Control labels. Each: (icon)(space)((key))word. Click zone spans all.
  local labels = {
    build_label(ICON.play,      keyof("continue",   "c"), "",        "ontinue",    action("continue")),
    build_label(ICON.step_over, keyof("step_over",  "s"), "",        "tep",        action("step_over")),
    build_label(ICON.step_into, keyof("step_into",  "d"), "",        "escend",     action("step_into")),
    build_label(ICON.step_out,  keyof("step_out",   "r"), "",        "eturn",      action("step_out")),
    build_label(ICON.restart,   keyof("restart",    "R"), "",        "estart",     action("restart")),
    build_label(ICON.stop,      keyof("terminate",  "q"), "",        "uit",        action("terminate")),
    build_label("\xe2\x9d\x93", keyof("help",       "?"), "",        ")help" ~= nil and "help" or "help",
                function() require("turbo-debug.help").open() end),
  }
  -- Fix the last label's construction (the above is awkward because of the
  -- "(?)help" edge case where key is "?" and the "word" is just "help").
  labels[#labels] = {
    icon = "\xe2\x9d\x93",  -- ❓
    key  = keyof("help", "?"),
    head = "",
    tail = "help",
    fn   = function() require("turbo-debug.help").open() end,
    no_attach = true,  -- render as "❓ (?) help" with a space after )
  }

  -- dap.status() on the right
  local status_ok, status_msg = pcall(function() return require("dap").status() end)
  if not status_ok then status_msg = "" end
  local right = (status_msg ~= "" and (status_msg .. " ") or "")

  -- Build the content line piece by piece, tracking (col, end_col, hl) spans
  -- for extmarks AND (col, end_col, fn) zones for click dispatch.
  local pieces = { chip }  -- start with chip text
  local hl_spans = { { 0, #chip, state_hl } }
  click_zones = {}

  local function byte_col() return #table.concat(pieces) end

  for _, lb in ipairs(labels) do
    -- leading gap between labels
    local gap = "   "
    pieces[#pieces + 1] = gap

    local label_start = byte_col()
    -- icon
    pieces[#pieces + 1] = lb.icon
    pieces[#pieces + 1] = " "
    -- head + "(" + key + ")" + tail  (e.g. "run to (C) cursor" → head="run to " tail=" cursor")
    pieces[#pieces + 1] = lb.head
    local paren_open_col = byte_col()
    pieces[#pieces + 1] = "("
    local key_col = byte_col()
    pieces[#pieces + 1] = lb.key
    local key_end_col = byte_col()
    pieces[#pieces + 1] = ")"
    local paren_close_col = byte_col()
    if lb.no_attach then pieces[#pieces + 1] = " " end
    pieces[#pieces + 1] = lb.tail
    local label_end = byte_col()

    -- highlight: the paren+key differently
    hl_spans[#hl_spans + 1] = { label_start, label_end, "TurboDebugBarCtrl" }
    hl_spans[#hl_spans + 1] = { key_col, key_end_col, "TurboDebugBarKey" }

    click_zones[#click_zones + 1] = { label_start, label_end, lb.fn }
  end

  local line = table.concat(pieces)

  -- right-align the status text
  local line_dwidth = vim.fn.strdisplaywidth(line)
  local right_dwidth = vim.fn.strdisplaywidth(right)
  local pad = width - line_dwidth - right_dwidth
  if pad < 1 then pad = 1 end
  local padding = string.rep(" ", pad)
  local right_byte_start = #line + #padding
  line = line .. padding .. right

  -- safety: if content is still wider than window, truncate
  if vim.fn.strdisplaywidth(line) > width then
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

  -- content-line highlights
  for _, span in ipairs(hl_spans) do
    local col_start, col_end = span[1], span[2]
    if col_end > #line then col_end = #line end
    if col_start < col_end then
      pcall(vim.api.nvim_buf_set_extmark, bar_buf, bar_ns, 1, col_start, {
        end_row = 1, end_col = col_end, hl_group = span[3],
      })
    end
  end

  -- right-side status highlight
  if right ~= "" and right_byte_start < #line then
    pcall(vim.api.nvim_buf_set_extmark, bar_buf, bar_ns, 1, right_byte_start, {
      end_row = 1, end_col = #line, hl_group = "TurboDebugBarStatus",
    })
  end

  -- convert byte-based click zones to display-column-based for mouse lookup
  for i, z in ipairs(click_zones) do
    local text_before = line:sub(1, z[1])
    local text_through = line:sub(1, z[2])
    click_zones[i] = {
      vim.fn.strdisplaywidth(text_before),
      vim.fn.strdisplaywidth(text_through),
      z[3],
    }
  end
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

  -- click dispatch (both mouse button and drag — drag counts as click on bar_buf)
  vim.keymap.set("n", "<LeftMouse>", handle_bar_click, { buffer = bar_buf, silent = true, nowait = true })
  vim.keymap.set("n", "<LeftRelease>", "<Nop>", { buffer = bar_buf, silent = true, nowait = true })

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
  if vim.api.nvim_win_is_valid(win) then
    vim.wo[win].wrap          = true
    vim.wo[win].breakindent   = true
    vim.wo[win].linebreak     = true
    vim.wo[win].showbreak     = " " .. ICON.wrap_mark .. " "
    vim.wo[win].sidescrolloff = 0
    vim.wo[win].cursorline    = true
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
  if config.opts.stop_on_entry_when_no_breakpoints ~= false and not has_any_breakpoint() then
    launch_with_stop_on_entry()
  else
    dap.continue()
  end
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
