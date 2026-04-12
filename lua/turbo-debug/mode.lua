local config = require("turbo-debug.config")
local help = require("turbo-debug.help")

local M = {}

local active = false
local active_win = nil
local saved_winbar = nil

-- two floating chrome bars (both independent of lualine):
--   sbar = status bar pinned at the TOP of the editor.
--     Row 0: turbo-debug · {dap status} · DEBUG · STATE
--     Row 1: ─── separator
--   cbar = control bar pinned just above the statusline.
--     Row 0: ─── separator
--     Row 1: {controls}                                ❓ help
local sbar_win, sbar_buf = nil, nil
local cbar_win, cbar_buf = nil, nil

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
  restart    = "\xf0\x9f\x94\x84",              -- 🔄 counterclockwise arrows (U+1F504). ♻️
                                                -- (U+267B + VS16) doesn't render in the
                                                -- user's font — VS16 forces emoji only
                                                -- when the font has an emoji glyph, and
                                                -- many don't. Supplementary plane is
                                                -- guaranteed color.
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
  help        = "\xe2\x9d\x93",                 -- ❓ black question mark ornament
                                                -- (U+2753). It's BMP but is
                                                -- Emoji_Presentation by default,
                                                -- so modern terminals render it
                                                -- as color. The previous attempt
                                                -- appeared broken only because
                                                -- of a misaligned extmark; with
                                                -- that gone, ❓ renders fine.

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

  -- Console height: 15% of the available vertical space, floored at 5 rows.
  -- "Available" = screen rows minus our two 3-row bars, the statusline,
  -- and the cmdline. With Breakpoints at 25% of a much-taller sidebar,
  -- Bp visibly exceeds Console so the user can see they're separate panes.
  local top_bar_rows    = 3
  local bottom_bar_rows = 3
  local statusline_rows = vim.o.laststatus > 0 and 1 or 0
  local cmdline_rows    = math.max(1, vim.o.cmdheight)
  local avail = vim.o.lines - top_bar_rows - bottom_bar_rows - statusline_rows - cmdline_rows
  if avail < 10 then avail = 10 end
  local console_size = math.max(5, math.floor(avail * 0.15))

  -- Sidebar width: ideal 40 cols, never less than 25, never more than 1/3
  -- of tty width. Scales down gracefully on narrow terminals, stops at 40
  -- on wide ones so the source area stays the star.
  local sidebar_size = math.max(25, math.min(40, math.floor(vim.o.columns / 3)))

  return {
    {
      position = pos,
      size = sidebar_size,
      -- Order: Call Stack → Scopes → Watches → Breakpoints.
      -- Equal 25% share per user preference.
      elements = {
        { id = "stacks",      size = 0.25 },
        { id = "scopes",      size = 0.25 },
        { id = "watches",     size = 0.25 },
        { id = "breakpoints", size = 0.25 },
      },
    },
    {
      -- Console only. REPL removed — hit E in debug mode to open it
      -- as a floating widget when needed.
      position = "bottom",
      size = console_size,
      elements = {
        { id = "console", size = 1.0 },
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
  hl(0, "TurboDebugBarBrand",       { default = true, link = "Title" })
  hl(0, "TurboDebugBarReady",       { default = true, link = "DiagnosticHint" })
  hl(0, "TurboDebugBarRunning",     { default = true, link = "DiagnosticInfo" })
  hl(0, "TurboDebugBarPaused",      { default = true, link = "DiagnosticError" })

  -- The key letter inside (c)ontinue etc. gets bold + Special's fg.
  -- No underline — the descender on lowercase q/g/p/y overlaps the
  -- underline and makes the glyph unreadable (q reads as g, etc.).
  -- nvim_set_hl can't combine link + bold, so copy Special's fg explicitly.
  -- Re-applied on ColorScheme so theme swaps don't blank it out.
  local function apply_key_hl()
    local ok, src = pcall(vim.api.nvim_get_hl, 0, { name = "Special", link = false })
    if not ok or not src or not src.fg then
      vim.api.nvim_set_hl(0, "TurboDebugBarKey", { default = true, link = "Special" })
      return
    end
    vim.api.nvim_set_hl(0, "TurboDebugBarKey", {
      fg = src.fg, bg = src.bg, bold = true, default = true,
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

-- ─── chrome bars (top = status, bottom = controls) ─────────────────────────
--
-- Both bars are floating windows with buffer-rendered content (winbar
-- doesn't render reliably in minimal-style floats). Highlights via
-- extmarks; mouse click dispatch via buffer-local <LeftMouse> keymap +
-- per-zone display-column lookup.

local bar_ns = vim.api.nvim_create_namespace("turbo-debug.bar")

-- click zones, one table per bar. Each entry: { line_1based, dcol_start, dcol_end, fn }
local sbar_zones = {}
local cbar_zones = {}

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

local function render_sbar()
  if not (sbar_buf and vim.api.nvim_buf_is_valid(sbar_buf)) then return end
  if not (sbar_win and vim.api.nvim_win_is_valid(sbar_win)) then return end

  local width = vim.api.nvim_win_get_width(sbar_win)
  if width < 1 then width = vim.o.columns end
  local sep = string.rep(ICON.hline, width)

  local state, state_hl = dap_state()

  -- layout on content row: [brand]   [status msg]   [state chip]
  local brand_text = " turbo-debug "
  local status_ok, status_msg = pcall(function() return require("dap").status() end)
  if not status_ok then status_msg = "" end

  local state_chip = " DEBUG " .. ICON.divider .. " " .. state .. " "

  local brand_dw = vim.fn.strdisplaywidth(brand_text)
  local chip_dw = vim.fn.strdisplaywidth(state_chip)

  local status_dw = vim.fn.strdisplaywidth(status_msg)
  local available = width - brand_dw - chip_dw - 4
  if status_dw > available and available > 5 then
    status_msg = status_msg:sub(1, available - 1) .. ICON.ellipsis
    status_dw = vim.fn.strdisplaywidth(status_msg)
  elseif available <= 5 then
    status_msg = ""
    status_dw = 0
  end

  local remain = width - brand_dw - status_dw - chip_dw
  if remain < 2 then remain = 2 end
  local pad_left = math.floor(remain / 2)
  local pad_right = remain - pad_left
  local content_line = brand_text .. string.rep(" ", pad_left) .. status_msg .. string.rep(" ", pad_right) .. state_chip

  -- 3 rows: sep / content / sep
  vim.bo[sbar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(sbar_buf, 0, -1, false, { sep, content_line, sep })
  vim.bo[sbar_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(sbar_buf, bar_ns, 0, -1)
  -- separators
  pcall(vim.api.nvim_buf_set_extmark, sbar_buf, bar_ns, 0, 0, {
    end_row = 0, end_col = #sep, hl_group = "TurboDebugBarSeparator",
  })
  pcall(vim.api.nvim_buf_set_extmark, sbar_buf, bar_ns, 2, 0, {
    end_row = 2, end_col = #sep, hl_group = "TurboDebugBarSeparator",
  })
  -- content: brand on left
  pcall(vim.api.nvim_buf_set_extmark, sbar_buf, bar_ns, 1, 0, {
    end_row = 1, end_col = #brand_text, hl_group = "TurboDebugBarBrand",
  })
  -- status message in the middle
  if status_dw > 0 then
    local status_byte_start = #brand_text + pad_left
    pcall(vim.api.nvim_buf_set_extmark, sbar_buf, bar_ns, 1, status_byte_start, {
      end_row = 1, end_col = status_byte_start + #status_msg, hl_group = "TurboDebugBarStatus",
    })
  end
  -- state chip on right
  local chip_byte_start = #content_line - #state_chip
  pcall(vim.api.nvim_buf_set_extmark, sbar_buf, bar_ns, 1, chip_byte_start, {
    end_row = 1, end_col = #content_line, hl_group = state_hl,
  })

  sbar_zones = {}
end

local function render_cbar()
  if not (cbar_buf and vim.api.nvim_buf_is_valid(cbar_buf)) then return end
  if not (cbar_win and vim.api.nvim_win_is_valid(cbar_win)) then return end

  local width = vim.api.nvim_win_get_width(cbar_win)
  if width < 1 then width = vim.o.columns end
  local sep = string.rep(ICON.hline, width)

  local state, _ = dap_state()
  local help_text = ICON.help .. " help "
  local help_dw = vim.fn.strdisplaywidth(help_text)

  -- Modal control labels. State-dependent text so the label shows what
  -- the key will ACTUALLY do right now:
  --   no session:  (c) start     (q)uit
  --   active:      (c)ontinue    (q) terminate
  local has_session = state ~= "READY"
  local continue_icon = has_session and ICON.go or ICON.start_rkt
  local continue_tail = has_session and "ontinue" or " start"
  local quit_tail = has_session and " terminate" or "uit"

  local controls = {
    { icon = continue_icon,  key = keyof("continue",  "c"), tail = continue_tail, fn = action("continue")  },
    { icon = ICON.step_over, key = keyof("step_over", "s"), tail = "tep",         fn = action("step_over") },
    { icon = ICON.step_into, key = keyof("step_into", "d"), tail = "escend",      fn = action("step_into") },
    { icon = ICON.step_out,  key = keyof("step_out",  "r"), tail = "eturn",       fn = action("step_out")  },
    { icon = ICON.restart,   key = keyof("restart",   "R"), tail = "estart",      fn = action("restart")   },
    { icon = ICON.stop,      key = keyof("terminate", "q"), tail = quit_tail,     fn = action("terminate") },
  }

  local ctrl_parts = {}
  local ctrl_spans = {}
  local ctrl_key_spans = {}
  local ctrl_zones_bytes = {}
  local gap = "   "
  for i, c in ipairs(controls) do
    local prefix_len = #table.concat(ctrl_parts)
    if i > 1 then
      ctrl_parts[#ctrl_parts + 1] = gap
      prefix_len = prefix_len + #gap
    end
    local txt, kcol, kend = build_control_text(c.icon, c.key, c.tail)
    ctrl_parts[#ctrl_parts + 1] = txt
    ctrl_spans[#ctrl_spans + 1] = { prefix_len, prefix_len + #txt, "TurboDebugBarCtrl" }
    ctrl_key_spans[#ctrl_key_spans + 1] = { prefix_len + kcol, prefix_len + kend }
    ctrl_zones_bytes[#ctrl_zones_bytes + 1] = { prefix_len, prefix_len + #txt, c.fn }
  end
  local controls_text = table.concat(ctrl_parts)
  local controls_dw = vim.fn.strdisplaywidth(controls_text)

  -- controls centered between left edge and help (right anchor)
  local ctrl_zone_width = width - help_dw
  local ctrl_pad_left = math.floor((ctrl_zone_width - controls_dw) / 2)
  if ctrl_pad_left < 1 then ctrl_pad_left = 1 end
  local ctrl_pad_right = ctrl_zone_width - controls_dw - ctrl_pad_left
  if ctrl_pad_right < 1 then ctrl_pad_right = 1 end
  local content_line = string.rep(" ", ctrl_pad_left) .. controls_text .. string.rep(" ", ctrl_pad_right) .. help_text

  -- 3 rows: sep / content / sep
  vim.bo[cbar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(cbar_buf, 0, -1, false, { sep, content_line, sep })
  vim.bo[cbar_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(cbar_buf, bar_ns, 0, -1)
  pcall(vim.api.nvim_buf_set_extmark, cbar_buf, bar_ns, 0, 0, {
    end_row = 0, end_col = #sep, hl_group = "TurboDebugBarSeparator",
  })
  pcall(vim.api.nvim_buf_set_extmark, cbar_buf, bar_ns, 2, 0, {
    end_row = 2, end_col = #sep, hl_group = "TurboDebugBarSeparator",
  })

  -- control labels (content is on row 1, index 1)
  local ctrl_byte_offset = ctrl_pad_left
  for _, span in ipairs(ctrl_spans) do
    pcall(vim.api.nvim_buf_set_extmark, cbar_buf, bar_ns, 1, ctrl_byte_offset + span[1], {
      end_row = 1, end_col = ctrl_byte_offset + span[2], hl_group = span[3],
    })
  end
  for _, span in ipairs(ctrl_key_spans) do
    pcall(vim.api.nvim_buf_set_extmark, cbar_buf, bar_ns, 1, ctrl_byte_offset + span[1], {
      end_row = 1, end_col = ctrl_byte_offset + span[2], hl_group = "TurboDebugBarKey",
    })
  end

  -- help (right-anchored)
  local help_byte_start = #content_line - #help_text
  pcall(vim.api.nvim_buf_set_extmark, cbar_buf, bar_ns, 1, help_byte_start, {
    end_row = 1, end_col = #content_line, hl_group = "TurboDebugBarCtrl",
  })

  cbar_zones = {}
  for _, z in ipairs(ctrl_zones_bytes) do
    local byte_start = ctrl_byte_offset + z[1]
    local byte_end = ctrl_byte_offset + z[2]
    local dcol_start = vim.fn.strdisplaywidth(content_line:sub(1, byte_start))
    local dcol_end   = vim.fn.strdisplaywidth(content_line:sub(1, byte_end))
    cbar_zones[#cbar_zones + 1] = { 2, dcol_start, dcol_end, z[3] }
  end
  -- help click zone (also on row 2 since the content is the middle row of 3)
  local help_dcol_start = vim.fn.strdisplaywidth(content_line:sub(1, help_byte_start))
  local help_dcol_end   = vim.fn.strdisplaywidth(content_line)
  cbar_zones[#cbar_zones + 1] = { 2, help_dcol_start, help_dcol_end,
                                   function() require("turbo-debug.help").open() end }
end

local function render_bars()
  render_sbar()
  render_cbar()
end

-- The bars are SPLITS, not floats. Splits consume real layout rows so
-- dapui and source windows tuck underneath them naturally — no overlap.

local function handle_sbar_click()
  local pos = vim.fn.getmousepos()
  if not pos or pos.winid ~= sbar_win then return end
  for _, zone in ipairs(sbar_zones) do
    if zone[1] == pos.line and pos.wincol - 1 >= zone[2] and pos.wincol - 1 < zone[3] then
      zone[4]()
      return
    end
  end
end

local function handle_cbar_click()
  local pos = vim.fn.getmousepos()
  if not pos or pos.winid ~= cbar_win then return end
  for _, zone in ipairs(cbar_zones) do
    if zone[1] == pos.line and pos.wincol - 1 >= zone[2] and pos.wincol - 1 < zone[3] then
      zone[4]()
      return
    end
  end
end

local function setup_bar_buf(buf)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].filetype = "TurboDebugBar"
end

local function setup_bar_win(win)
  vim.wo[win].winhighlight = "Normal:TurboDebugBar,EndOfBuffer:TurboDebugBar"
  vim.wo[win].winfixheight = true
  vim.wo[win].list = false
  vim.wo[win].cursorline = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].statuscolumn = ""
  vim.wo[win].wrap = false
end

local function bounce_out(buf)
  -- if focus lands in a bar buffer (e.g. mouse drag), kick it back out
  -- so the user can't accidentally type into a non-modifiable buffer.
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_get_current_buf() == buf then
          pcall(vim.cmd, "wincmd p")
        end
      end)
    end,
  })
end

local function open_bars()
  -- Both bars are SPLITS, not floats. Splits consume real layout rows
  -- so dapui and source windows tuck underneath them rather than
  -- getting overlaid. The caller's original focus is preserved.
  local caller_win = vim.api.nvim_get_current_win()

  -- status bar (top)
  if not (sbar_win and vim.api.nvim_win_is_valid(sbar_win)) then
    vim.cmd("noautocmd keepalt topleft split")
    sbar_win = vim.api.nvim_get_current_win()
    sbar_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(sbar_win, sbar_buf)
    vim.api.nvim_win_set_height(sbar_win, 3)
    setup_bar_buf(sbar_buf)
    setup_bar_win(sbar_win)
    vim.wo[sbar_win].winfixheight = true
    vim.keymap.set("n", "<LeftMouse>", handle_sbar_click, { buffer = sbar_buf, silent = true, nowait = true })
    vim.keymap.set("n", "<LeftRelease>", "<Nop>", { buffer = sbar_buf, silent = true, nowait = true })
    bounce_out(sbar_buf)
  end

  -- back to caller before creating bottom so topology is predictable
  if vim.api.nvim_win_is_valid(caller_win) then
    pcall(vim.api.nvim_set_current_win, caller_win)
  end

  -- control bar (bottom)
  if not (cbar_win and vim.api.nvim_win_is_valid(cbar_win)) then
    vim.cmd("noautocmd keepalt botright split")
    cbar_win = vim.api.nvim_get_current_win()
    cbar_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(cbar_win, cbar_buf)
    vim.api.nvim_win_set_height(cbar_win, 3)
    setup_bar_buf(cbar_buf)
    setup_bar_win(cbar_win)
    vim.wo[cbar_win].winfixheight = true
    vim.keymap.set("n", "<LeftMouse>", handle_cbar_click, { buffer = cbar_buf, silent = true, nowait = true })
    vim.keymap.set("n", "<LeftRelease>", "<Nop>", { buffer = cbar_buf, silent = true, nowait = true })
    bounce_out(cbar_buf)
  end

  -- restore caller focus
  if vim.api.nvim_win_is_valid(caller_win) then
    pcall(vim.api.nvim_set_current_win, caller_win)
  end

  render_bars()
end

local function close_bars()
  if sbar_win and vim.api.nvim_win_is_valid(sbar_win) then
    pcall(vim.api.nvim_win_close, sbar_win, true)
  end
  if cbar_win and vim.api.nvim_win_is_valid(cbar_win) then
    pcall(vim.api.nvim_win_close, cbar_win, true)
  end
  sbar_win, sbar_buf, cbar_win, cbar_buf = nil, nil, nil, nil
  sbar_zones, cbar_zones = {}, {}
end

local function reposition_bars()
  -- Splits auto-track VimResized via winfixheight; just re-render content.
  render_bars()
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
  local function refresh_bars() vim.schedule(render_bars) end
  dap.listeners.after.event_initialized["turbo-debug-bar"]  = refresh_bars
  dap.listeners.after.event_stopped["turbo-debug-bar"]      = refresh_bars
  dap.listeners.after.event_continued["turbo-debug-bar"]    = refresh_bars
  dap.listeners.after.event_terminated["turbo-debug-bar"]   = refresh_bars
  dap.listeners.after.event_exited["turbo-debug-bar"]       = refresh_bars

  dap.listeners.after.event_stopped["turbo-debug-ip"] = function(session, body)
    vim.defer_fn(function()
      clear_ip()
      local frame = session and session.current_frame
      if not (frame and frame.source and frame.source.path) then return end
      local buf = vim.fn.bufnr(frame.source.path)
      if buf == -1 or not vim.api.nvim_buf_is_valid(buf) then return end
      local line = math.max(0, (frame.line or 1) - 1)
      local reason = ((body and body.reason) or "stopped"):upper()
      -- Extmark carries BOTH the virt_text (👈 REASON at EOL) AND a
      -- sign_text (👉 in the gutter) with high priority. nvim-dap also
      -- places its own DapStopped sign, but at the same priority as the
      -- breakpoint sign — which meant whichever was placed later won.
      -- Our extmark sign at priority 500 always wins, guaranteeing the
      -- paused line has the finger-pointing icon in the gutter.
      pcall(vim.api.nvim_buf_set_extmark, buf, ip_ns, line, 0, {
        sign_text     = "\xf0\x9f\x91\x89",  -- 👉 U+1F449
        sign_hl_group = "DapStopped",
        virt_text = {
          { "  " .. ICON.ip_left .. "  ", "DapStopped" },
          { reason,                       "TurboDebugIPReason" },
        },
        virt_text_pos = "eol",
        hl_mode = "combine",
        priority = 500,
      })
    end, 50)
  end
  dap.listeners.after.event_continued["turbo-debug-ip"]  = function() clear_ip() end
  dap.listeners.before.event_terminated["turbo-debug-ip"] = function() clear_ip() end
  dap.listeners.before.event_exited["turbo-debug-ip"]     = function() clear_ip() end

  -- winbar titles on dapui panes — colorful emoji for instant pane
  -- recognition. REPL is iconless per user preference (its prompt is
  -- already visually distinct enough).
  local titles = {
    dapui_scopes      = " " .. ICON.scopes      .. "  Scopes",
    dapui_watches     = " " .. ICON.watches     .. "  Watches",
    dapui_stacks      = " " .. ICON.stacks      .. "  Call Stack",
    dapui_breakpoints = " " .. ICON.breakpoints .. "  Breakpoints",
    dapui_console     = " " .. ICON.terminal    .. "  Console",
    ["dap-repl"]      = " REPL",
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
  -- Source file's winbar is just the filename now — the "DEBUG · STATE"
  -- chip lives in the top status bar (sbar). Keeps the source context
  -- minimal and leaves more room for filename paths.
  vim.wo[active_win].winbar = " %f"
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
    callback = reposition_bars,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M._install_for_buf(buf) end
  end

  set_debug_chrome()
  ensure_dapui()
  require("dapui").open()
  open_bars()

  -- second install pass after dapui has created its buffers
  vim.schedule(function()
    if not active then return end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then M._install_for_buf(buf) end
    end
    reposition_bars()
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
  close_bars()
  help.close()

  if dapui_initialized then require("dapui").close() end
  if vt_initialized then require("nvim-dap-virtual-text").disable() end
end

function M.toggle()
  if active then M.exit() else M.enter() end
end

function M.is_active() return active end

return M
