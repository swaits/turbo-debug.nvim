local config = require("turbo-debug.config")
local help = require("turbo-debug.help")

local M = {}

local active = false
local active_win = nil
local saved_winbar = nil

-- Forward declaration so listeners registered in ensure_dapui (which is
-- defined earlier in the file than source_window) can still reference it
-- as an upvalue rather than a nil global.
local source_window

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

-- Tracks the total vertical rows currently available to the dapui layout
-- (sum of all open dapui pane heights). When this changes — e.g. bufferline
-- tabline appears or disappears, reclaiming/returning a row — dapui's
-- `win_states.size` proportions go stale (dapui has no WinResized listener
-- of its own), and nvim arbitrarily gives the delta row to one pane, which
-- then renders EOB `~` below its content. On detected change we re-pin to
-- our initial proportions.
local last_dapui_total_height = nil

-- The user's theme's WinSeparator highlight, captured on debug-mode enter
-- before we override it to the bright TurboDebugBarSeparator color. We
-- want EVERY horizontal/vertical split divider in the editor to match our
-- bar separator style during a debug session — the dim default makes
-- dapui's pane-to-pane boundaries look like a visual seam, while the
-- bright override gives the whole debug UI a single consistent chrome
-- color. Restored byte-for-byte on M.exit.
local saved_winsep_hl = nil

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
  watches     = "\xf0\x9f\x91\x80",             -- 👀 eyes (U+1F440)
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

  -- Console height: max(8 rows, 20% of total editor lines). More
  -- generous than the previous 15% — user reported the Console kept
  -- feeling "laughably small" so we're allocating real estate.
  local console_size = config.opts.console_height
                       or math.max(8, math.floor(vim.o.lines * 0.2))

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
  -- Bar background: link to Normal so the bar blends with dapui's own
  -- pane borders (which use Normal or WinBar — both share the editor's
  -- default background). StatusLine was too dark and created a visible
  -- seam between the bar and the surrounding panes.
  hl(0, "TurboDebugBar",            { default = true, link = "Normal" })
  -- Bar separator: fg derived from WinBar.fg at runtime so it matches
  -- whatever color the user's theme uses for pane-title chrome
  -- (dapui renders each pane's title in its winbar, so this is
  -- THE visible "chrome" color). Theme-agnostic — works with any
  -- colorscheme. Falls back to WinSeparator if WinBar has no fg.
  -- Re-applied on ColorScheme so theme swaps keep it in sync.
  --
  -- Placeholder link so the group exists as a sane default even
  -- before the derive runs.
  hl(0, "TurboDebugBarSeparator",   { default = true, link = "WinSeparator" })
  -- Control labels: link to Normal so the text blends with the bar's
  -- Normal-bg surface. StatusLine bg was creating a visible color patch
  -- behind each label. The key letter still pops via TurboDebugBarKey
  -- (Special fg, bold), and icons carry their own emoji color.
  hl(0, "TurboDebugBarCtrl",        { default = true, link = "Normal" })
  hl(0, "TurboDebugBarStatus",      { default = true, link = "Comment" })
  hl(0, "TurboDebugBarBrand",       { default = true, link = "Title" })
  hl(0, "TurboDebugBarReady",       { default = true, link = "DiagnosticHint" })
  hl(0, "TurboDebugBarRunning",     { default = true, link = "DiagnosticInfo" })
  hl(0, "TurboDebugBarPaused",      { default = true, link = "DiagnosticError" })
  -- Italic qualifier words ("over", "into", "out") shown after the
  -- step/descend/return labels. Subordinate styling: Comment fg + italic,
  -- so the key label ("(s)tep") reads primary and the qualifier ("over")
  -- reads secondary. Can't combine link+italic via nvim_set_hl; derive
  -- fg from Comment and set italic explicitly.
  local function apply_italic_hl()
    local ok, src = pcall(vim.api.nvim_get_hl, 0, { name = "Comment", link = false })
    if not ok or not src or not src.fg then
      vim.api.nvim_set_hl(0, "TurboDebugBarItalic", { default = true, link = "Comment" })
      return
    end
    vim.api.nvim_set_hl(0, "TurboDebugBarItalic", {
      fg = src.fg, italic = true, default = true,
    })
  end
  apply_italic_hl()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("TurboDebugBarItalicHL", { clear = true }),
    callback = apply_italic_hl,
  })

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

  -- Separator color: derive from WinBar.fg at runtime. Every theme
  -- stylistically renders WinBar (pane-title chrome) in a color
  -- that's intentionally visible against Normal — which is exactly
  -- the semantic we want for our bar edges. Theme-agnostic. If
  -- WinBar has no fg (very rare), fall back to WinSeparator so
  -- we at least match the theme's split-divider convention.
  --
  -- Also override the global WinSeparator to the same fg during
  -- debug mode, so every split divider in the editor matches our
  -- bar chrome (dapui pane-to-pane, source-to-console, our bars to
  -- their neighbors — all one consistent color). Original captured
  -- on first call, restored in M.exit.
  local function apply_sep_hl()
    local ok, src = pcall(vim.api.nvim_get_hl, 0, { name = "WinBar", link = false })
    if ok and src and src.fg then
      -- Not `default = true` — we MUST override the placeholder link
      -- we set in the table-of-defaults above. default semantics
      -- would leave the placeholder in place.
      vim.api.nvim_set_hl(0, "TurboDebugBarSeparator", { fg = src.fg })
      if saved_winsep_hl == nil then
        local wok, ws = pcall(vim.api.nvim_get_hl, 0, { name = "WinSeparator", link = false })
        if wok then saved_winsep_hl = ws or {} end
      end
      vim.api.nvim_set_hl(0, "WinSeparator", { fg = src.fg })
      return
    end
    vim.api.nvim_set_hl(0, "TurboDebugBarSeparator", { link = "WinSeparator" })
  end
  apply_sep_hl()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("TurboDebugBarSepHL", { clear = true }),
    callback = apply_sep_hl,
  })
end

-- winhighlight strings applied to dapui panes. `WinBar:WinBar,WinBarNC:WinBar`
-- is defensive — if the user's theme makes WinBarNC dimmer than WinBar, this
-- forces the pane's winbar row to stay bright even when the pane is
-- unfocused (nvim renders unfocused wins with WinBarNC). Nordfox happens to
-- make them identical; other themes don't.
local DAPUI_WINHL_ACTIVE = "WinBar:WinBar,WinBarNC:WinBar,WinSeparator:TurboDebugBorderActive,FloatBorder:TurboDebugBorderActive"
local DAPUI_WINHL_INACTIVE = "WinBar:WinBar,WinBarNC:WinBar,WinSeparator:TurboDebugBorderInactive,FloatBorder:TurboDebugBorderInactive"

local function setup_active_win_highlights()
  local active_hl = DAPUI_WINHL_ACTIVE
  local inactive_hl = DAPUI_WINHL_INACTIVE

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

-- Build a label's byte-level representation.
-- Format: "<icon> (<key>)<tail>[ <italic>]"
--   e.g.  ` (s)tep over`  with `over` styled italic.
-- Returns: text, key_col, key_end_col, italic_col, italic_end_col
--   (italic_col/italic_end_col are nil when italic is not set).
local function build_control_text(icon, key, tail, italic)
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
  local italic_col, italic_end_col
  if italic and italic ~= "" then
    add(" ")
    italic_col = col()
    add(italic)
    italic_end_col = col()
  end

  return table.concat(parts), key_col, key_end_col, italic_col, italic_end_col
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

  -- 2 rows: top sep / content. Only the outward (top) edge gets a bright
  -- separator; the inward edge abuts dapui's top pane (whose winbar and
  -- nvim's own horiz separator serve as the visual boundary there). Keeps
  -- the bar's vertical footprint minimal.
  vim.bo[sbar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(sbar_buf, 0, -1, false, { sep, content_line })
  vim.bo[sbar_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(sbar_buf, bar_ns, 0, -1)
  pcall(vim.api.nvim_buf_set_extmark, sbar_buf, bar_ns, 0, 0, {
    end_row = 0, end_col = #sep, hl_group = "TurboDebugBarSeparator",
  })
  -- content row
  pcall(vim.api.nvim_buf_set_extmark, sbar_buf, bar_ns, 1, 0, {
    end_row = 1, end_col = #brand_text, hl_group = "TurboDebugBarBrand",
  })
  if status_dw > 0 then
    local status_byte_start = #brand_text + pad_left
    pcall(vim.api.nvim_buf_set_extmark, sbar_buf, bar_ns, 1, status_byte_start, {
      end_row = 1, end_col = status_byte_start + #status_msg, hl_group = "TurboDebugBarStatus",
    })
  end
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
  --   no session:  (c) start     (q)uit         (Restart hidden)
  --   active:      (c)ontinue    (q) terminate  (R)estart shown
  local has_session = state ~= "READY"
  local continue_icon = has_session and ICON.go or ICON.start_rkt
  local continue_tail = has_session and "ontinue" or " start"
  local quit_tail = has_session and " terminate" or "uit"

  local controls = {
    { icon = continue_icon,  key = keyof("continue",  "c"), tail = continue_tail, italic = nil,    fn = action("continue")  },
    { icon = ICON.step_over, key = keyof("step_over", "s"), tail = "tep",         italic = "over", fn = action("step_over") },
    { icon = ICON.step_into, key = keyof("step_into", "d"), tail = "escend",      italic = "into", fn = action("step_into") },
    { icon = ICON.step_out,  key = keyof("step_out",  "r"), tail = "eturn",       italic = "out",  fn = action("step_out")  },
  }
  -- (R)estart is only meaningful during an active session
  if has_session then
    controls[#controls + 1] = { icon = ICON.restart, key = keyof("restart", "R"), tail = "estart", italic = nil, fn = action("restart") }
  end
  controls[#controls + 1] = { icon = ICON.stop, key = keyof("terminate", "q"), tail = quit_tail, italic = nil, fn = action("terminate") }

  local gap = "   "
  local function build_controls(include_italic)
    local parts, spans, key_spans, italic_spans, zones = {}, {}, {}, {}, {}
    for i, c in ipairs(controls) do
      local prefix_len = #table.concat(parts)
      if i > 1 then
        parts[#parts + 1] = gap
        prefix_len = prefix_len + #gap
      end
      local italic_text = include_italic and c.italic or nil
      local txt, kcol, kend, icol, iend = build_control_text(c.icon, c.key, c.tail, italic_text)
      parts[#parts + 1] = txt
      spans[#spans + 1] = { prefix_len, prefix_len + #txt, "TurboDebugBarCtrl" }
      key_spans[#key_spans + 1] = { prefix_len + kcol, prefix_len + kend }
      if icol then
        italic_spans[#italic_spans + 1] = { prefix_len + icol, prefix_len + iend }
      end
      zones[#zones + 1] = { prefix_len, prefix_len + #txt, c.fn }
    end
    return table.concat(parts), spans, key_spans, italic_spans, zones
  end

  -- Try with italic qualifiers first; fall back to the compact form if
  -- the label row would overflow the available width. Min 1-char padding
  -- on each side of the controls-plus-help block.
  local controls_text, ctrl_spans, ctrl_key_spans, ctrl_italic_spans, ctrl_zones_bytes =
    build_controls(true)
  local controls_dw = vim.fn.strdisplaywidth(controls_text)
  if controls_dw + help_dw + 2 > width then
    controls_text, ctrl_spans, ctrl_key_spans, ctrl_italic_spans, ctrl_zones_bytes =
      build_controls(false)
    controls_dw = vim.fn.strdisplaywidth(controls_text)
  end

  -- controls centered between left edge and help (right anchor)
  local ctrl_zone_width = width - help_dw
  local ctrl_pad_left = math.floor((ctrl_zone_width - controls_dw) / 2)
  if ctrl_pad_left < 1 then ctrl_pad_left = 1 end
  local ctrl_pad_right = ctrl_zone_width - controls_dw - ctrl_pad_left
  if ctrl_pad_right < 1 then ctrl_pad_right = 1 end
  local content_line = string.rep(" ", ctrl_pad_left) .. controls_text .. string.rep(" ", ctrl_pad_right) .. help_text

  -- 2 rows: content / bottom sep. Only the outward (bottom) edge gets a
  -- bright separator; the inward edge abuts dapui Console (whose winbar
  -- + nvim's own horiz separator serve as the visual boundary there).
  vim.bo[cbar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(cbar_buf, 0, -1, false, { content_line, sep })
  vim.bo[cbar_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(cbar_buf, bar_ns, 0, -1)
  pcall(vim.api.nvim_buf_set_extmark, cbar_buf, bar_ns, 1, 0, {
    end_row = 1, end_col = #sep, hl_group = "TurboDebugBarSeparator",
  })

  -- control labels on row 0 (content row)
  local ctrl_byte_offset = ctrl_pad_left
  for _, span in ipairs(ctrl_spans) do
    pcall(vim.api.nvim_buf_set_extmark, cbar_buf, bar_ns, 0, ctrl_byte_offset + span[1], {
      end_row = 0, end_col = ctrl_byte_offset + span[2], hl_group = span[3],
    })
  end
  for _, span in ipairs(ctrl_key_spans) do
    pcall(vim.api.nvim_buf_set_extmark, cbar_buf, bar_ns, 0, ctrl_byte_offset + span[1], {
      end_row = 0, end_col = ctrl_byte_offset + span[2], hl_group = "TurboDebugBarKey",
    })
  end
  for _, span in ipairs(ctrl_italic_spans) do
    pcall(vim.api.nvim_buf_set_extmark, cbar_buf, bar_ns, 0, ctrl_byte_offset + span[1], {
      end_row = 0, end_col = ctrl_byte_offset + span[2], hl_group = "TurboDebugBarItalic",
    })
  end

  local help_byte_start = #content_line - #help_text
  pcall(vim.api.nvim_buf_set_extmark, cbar_buf, bar_ns, 0, help_byte_start, {
    end_row = 0, end_col = #content_line, hl_group = "TurboDebugBarCtrl",
  })

  cbar_zones = {}
  for _, z in ipairs(ctrl_zones_bytes) do
    local byte_start = ctrl_byte_offset + z[1]
    local byte_end = ctrl_byte_offset + z[2]
    local dcol_start = vim.fn.strdisplaywidth(content_line:sub(1, byte_start))
    local dcol_end   = vim.fn.strdisplaywidth(content_line:sub(1, byte_end))
    -- content is on buffer row 0 = window line 1
    cbar_zones[#cbar_zones + 1] = { 1, dcol_start, dcol_end, z[3] }
  end
  local help_dcol_start = vim.fn.strdisplaywidth(content_line:sub(1, help_byte_start))
  local help_dcol_end   = vim.fn.strdisplaywidth(content_line)
  cbar_zones[#cbar_zones + 1] = { 1, help_dcol_start, help_dcol_end,
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
  -- CRITICAL: clear winbar first. `:topleft split` / `:botright split`
  -- inherits window-local options from the window we split off of. The
  -- caller is the source window, which has `winbar = " %f"` set by
  -- `set_debug_chrome`. Inherited onto the bar, that renders as an
  -- extra chrome row ABOVE our own separator (since winbar sits above
  -- the buffer rows), showing the scratch buffer's empty filename —
  -- the phantom "second separator" the user sees stacked above the
  -- legend bar. Explicit empty string disables the winbar entirely.
  vim.wo[win].winbar = ""
  -- Include StatusLine/StatusLineNC so any statusline row the bar
  -- might pick up (with laststatus=2 every window gets one) blends
  -- into the bar's Normal bg instead of rendering in the dark default
  -- StatusLine color — which was the "wrong color border below top bar".
  vim.wo[win].winhighlight = "Normal:TurboDebugBar,EndOfBuffer:TurboDebugBar,StatusLine:TurboDebugBar,StatusLineNC:TurboDebugBar"
  vim.wo[win].statusline = " "  -- empty content; hl makes it invisible
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
  -- so dapui windows tuck between them. `wincmd K` / `wincmd J` is
  -- applied after creation to ensure the bars span the FULL editor
  -- width (across the sidebar column too) — otherwise dapui's later
  -- vertical splits would constrain the bars to just the main column.
  local caller_win = vim.api.nvim_get_current_win()

  -- status bar (top)
  if not (sbar_win and vim.api.nvim_win_is_valid(sbar_win)) then
    vim.cmd("noautocmd keepalt topleft split")
    sbar_win = vim.api.nvim_get_current_win()
    sbar_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(sbar_win, sbar_buf)
    vim.api.nvim_win_set_height(sbar_win, 2)
    setup_bar_buf(sbar_buf)
    setup_bar_win(sbar_win)
    vim.wo[sbar_win].winfixheight = true
    vim.keymap.set("n", "<LeftMouse>", handle_sbar_click, { buffer = sbar_buf, silent = true, nowait = true })
    vim.keymap.set("n", "<LeftRelease>", "<Nop>", { buffer = sbar_buf, silent = true, nowait = true })
    bounce_out(sbar_buf)
  end

  if vim.api.nvim_win_is_valid(caller_win) then
    pcall(vim.api.nvim_set_current_win, caller_win)
  end

  -- control bar (bottom)
  if not (cbar_win and vim.api.nvim_win_is_valid(cbar_win)) then
    vim.cmd("noautocmd keepalt botright split")
    cbar_win = vim.api.nvim_get_current_win()
    cbar_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(cbar_win, cbar_buf)
    vim.api.nvim_win_set_height(cbar_win, 2)
    setup_bar_buf(cbar_buf)
    setup_bar_win(cbar_win)
    vim.wo[cbar_win].winfixheight = true
    vim.keymap.set("n", "<LeftMouse>", handle_cbar_click, { buffer = cbar_buf, silent = true, nowait = true })
    vim.keymap.set("n", "<LeftRelease>", "<Nop>", { buffer = cbar_buf, silent = true, nowait = true })
    bounce_out(cbar_buf)
  end

  if vim.api.nvim_win_is_valid(caller_win) then
    pcall(vim.api.nvim_set_current_win, caller_win)
  end

  render_bars()
end

-- Set dapui pane heights to their initial proportions. Called ONCE
-- per M.enter, after dapui.open(). No winfixheight — the user is free
-- to manually resize panes (bigger Breakpoints list, taller Console to
-- tail long output, etc.) and their resize sticks because we don't
-- fight subsequent WinResized events. Initial sizing only.
local function pin_dapui_sizes()
  local pane_wins = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local ft = vim.bo[buf].filetype
      if ft == "dapui_stacks" or ft == "dapui_scopes" or ft == "dapui_watches"
         or ft == "dapui_breakpoints" or ft == "dapui_console" or ft == "dap-repl" then
        local wins = vim.fn.win_findbuf(buf)
        if wins and wins[1] and vim.api.nvim_win_is_valid(wins[1]) then
          pane_wins[ft] = wins[1]
        end
      end
    end
  end

  -- Console to configured height
  if pane_wins.dapui_console then
    local target = config.opts.console_height
                   or math.max(8, math.floor(vim.o.lines * 0.2))
    pcall(vim.api.nvim_win_set_height, pane_wins.dapui_console, target)
  end

  -- Sidebar panes distributed equally (residual to Breakpoints)
  local order = { "dapui_stacks", "dapui_scopes", "dapui_watches", "dapui_breakpoints" }
  local present = {}
  local total = 0
  for _, ft in ipairs(order) do
    local w = pane_wins[ft]
    if w then
      present[#present + 1] = w
      total = total + vim.api.nvim_win_get_height(w)
    end
  end
  if #present > 1 and total > 0 then
    local each = math.floor(total / #present)
    local residual = total - (each * #present)
    for i, w in ipairs(present) do
      local h = each + (i == #present and residual or 0)
      pcall(vim.api.nvim_win_set_height, w, h)
    end
  end
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

-- `winfixheight` is a preference, not a guarantee. Under grid pressure
-- (bufferline tabline appearing/disappearing, `wincmd =`, etc.) nvim will
-- shrink OR grow a bar against its fixed-height mark:
--
--   shrinking below 2 rows → bar content is clipped; first/second row
--       invisible, the bar looks "squished".
--   growing above 2 rows → the extra row sits past the end of the 2-line
--       buffer and renders as a stray `~` EOB marker (between our sep
--       and the next window).
--
-- Clamp EXACTLY to 2 on every resize event. When we shrink an oversized
-- bar, the row nvim gave us has to go somewhere else; on WinResized the
-- subsequent pin_dapui_sizes() call redistributes it across the dapui
-- panes according to our initial proportions.
local function ensure_bar_heights()
  if sbar_win and vim.api.nvim_win_is_valid(sbar_win) then
    if vim.api.nvim_win_get_height(sbar_win) ~= 2 then
      pcall(vim.api.nvim_win_set_height, sbar_win, 2)
    end
  end
  if cbar_win and vim.api.nvim_win_is_valid(cbar_win) then
    if vim.api.nvim_win_get_height(cbar_win) ~= 2 then
      pcall(vim.api.nvim_win_set_height, cbar_win, 2)
    end
  end
end

-- Sum the heights of all currently-open dapui pane windows. Used to detect
-- external geometry changes (tabline toggle) without false-positive firing
-- on user-internal resizes (which redistribute within the total area
-- without changing it).
local function compute_dapui_total_height()
  local total = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local ft = vim.bo[buf].filetype
      if ft == "dapui_stacks" or ft == "dapui_scopes" or ft == "dapui_watches"
         or ft == "dapui_breakpoints" or ft == "dapui_console" or ft == "dap-repl" then
        for _, win in ipairs(vim.fn.win_findbuf(buf)) do
          if vim.api.nvim_win_is_valid(win)
             and vim.api.nvim_win_get_config(win).relative == "" then
            total = total + vim.api.nvim_win_get_height(win)
          end
        end
      end
    end
  end
  return total
end

local function reposition_bars()
  -- Just re-render bar content. We intentionally DON'T re-pin dapui
  -- sizes here — the user may have manually resized panes, and
  -- fighting their resize on every event is a worse UX than occasional
  -- layout drift.
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
    -- Baseline winhighlight so WinBarNC:WinBar is in effect from the
    -- first render (not just after the first WinEnter/WinLeave cycle).
    -- setup_active_win_highlights overwrites on focus change.
    vim.wo[win].winhighlight   = DAPUI_WINHL_INACTIVE
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
  -- One-time setup. Calling dapui.setup on every enter was tearing down
  -- internal state (windows, event listeners, buffer refs) while the
  -- adapter handshake was in flight — "Debug adapter didn't respond"
  -- timeouts and overall slowness. dapui's layouts use the absolute
  -- sizes computed once here; if the terminal resizes significantly
  -- between toggles, proportions can drift slightly, but that's
  -- acceptable compared to breaking the adapter.
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

  -- When a stopped event fires, dap will jump to the source frame using
  -- its switchbuf logic. `uselast` (the common default) targets the
  -- CURRENT window — but if focus happens to be on a dapui pane or one
  -- of our bars, dap falls back to `winnr('#')` which can land anywhere
  -- (including bufferline's tabline area or a wrong split). By shifting
  -- focus to a real source window BEFORE dap processes the jump, we
  -- guarantee new source files (stepped-into library/stdlib files) open
  -- in the intended source window and the chrome stays intact.
  dap.listeners.before.event_stopped["turbo-debug-focus-source"] = function()
    local w = source_window()
    if w and w ~= vim.api.nvim_get_current_win() then
      pcall(vim.api.nvim_set_current_win, w)
    end
  end

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

  -- Clear the Console pane on session start/restart.
  --
  -- Strategy: keep the buffer (crucially, keep the attached terminal
  -- channel intact so dap's output stream isn't broken), briefly flip
  -- `modifiable` on and call nvim_buf_set_lines to wipe the scrollback.
  -- The terminal's PTY state and cursor position are preserved — only
  -- the displayed lines are removed. Next output from the program
  -- appends from the top of the empty buffer.
  --
  -- The previous "delete the whole buffer" approach only worked on
  -- fresh launches (new terminal opens anyway) and broke on Restart
  -- because the adapter reuses the existing terminal channel — deleting
  -- the buffer orphaned the channel and left the Console unresponsive.
  local function clear_console()
    if not config.opts.clear_console_on_start then return end
    local ok, dapui = pcall(require, "dapui")
    if not (ok and dapui.elements and dapui.elements.console) then return end
    local bok, buf = pcall(dapui.elements.console.buffer)
    if not bok or not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    pcall(function()
      local was_mod = vim.bo[buf].modifiable
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
      vim.bo[buf].modifiable = was_mod
    end)
  end
  -- Fire before every session-starting verb so old scrollback is gone
  -- before the new session's output begins.
  dap.listeners.before.launch["turbo-debug-clear-console"]  = clear_console
  dap.listeners.before.attach["turbo-debug-clear-console"]  = clear_console
  dap.listeners.before.restart["turbo-debug-clear-console"] = clear_console

  -- Default-collapse scopes the user considers noisy (Registers on
  -- codelldb, for example). We intercept the scopes response and set
  -- `expensive = true` on any matching scope — dapui's own component
  -- auto-collapses anything marked expensive (see dapui/components/
  -- scopes.lua line 22-24), so this reuses their existing mechanism.
  dap.listeners.before.scopes["turbo-debug-collapse"] = function(_, _, response, _)
    local collapse = config.opts.collapsed_scopes
    if not (collapse and #collapse > 0) then return end
    if not (response and response.scopes) then return end
    for _, scope in ipairs(response.scopes) do
      for _, name in ipairs(collapse) do
        if scope.name == name then
          scope.expensive = true
          break
        end
      end
    end
  end

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
-- NOTE: assigned (not declared) — forward-declared at top of file.
source_window = function()
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
  -- Editor resize: recreate any bar that got killed, un-squish any that
  -- got shrunk below 2 rows, then re-render. VimResized always changes
  -- the dapui area total (since vim.o.lines changed), so we re-pin
  -- proportions and update the cached total.
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      vim.schedule(function()
        if not active then return end
        if not (sbar_win and vim.api.nvim_win_is_valid(sbar_win)) then
          sbar_win, sbar_buf = nil, nil
        end
        if not (cbar_win and vim.api.nvim_win_is_valid(cbar_win)) then
          cbar_win, cbar_buf = nil, nil
        end
        open_bars()
        ensure_bar_heights()
        pin_dapui_sizes()
        last_dapui_total_height = compute_dapui_total_height()
        render_bars()
      end)
    end,
  })
  -- WinResized fires on any geometry change: mouse-drags on split
  -- borders, bufferline's tabline appearing/disappearing (which
  -- reclaims/returns a row and can squish our bars), `wincmd =`, etc.
  -- Two separate concerns handled here:
  --   1. Bars squished / killed → recreate + force heights.
  --   2. Total dapui area changed (tabline toggle) → re-pin proportions
  --      so no pane ends up taller than its buffer (EOB `~` bug).
  -- We distinguish case 2 from a user-internal resize (dragging the
  -- Scopes/Watches border) by comparing the TOTAL dapui height against
  -- last_dapui_total_height. User-internal resizes redistribute within
  -- the total; they don't change it — so their customization survives.
  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      if not active then return end
      vim.schedule(function()
        if not (sbar_win and vim.api.nvim_win_is_valid(sbar_win)) then
          sbar_win, sbar_buf = nil, nil
        end
        if not (cbar_win and vim.api.nvim_win_is_valid(cbar_win)) then
          cbar_win, cbar_buf = nil, nil
        end
        if not (sbar_win and cbar_win) then
          open_bars()
        end
        ensure_bar_heights()
        local dapui_total = compute_dapui_total_height()
        if last_dapui_total_height ~= nil
           and dapui_total ~= last_dapui_total_height then
          pin_dapui_sizes()
          dapui_total = compute_dapui_total_height()
        end
        last_dapui_total_height = dapui_total
        render_bars()
        pcall(vim.cmd, "redraw!")
      end)
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M._install_for_buf(buf) end
  end

  set_debug_chrome()
  ensure_dapui()
  -- { reset = true } is critical: without it, dapui's WindowLayout:resize
  -- uses whatever `win_state.size` drifted to last time (see
  -- dapui/windows/layout.lua:82-116 — `update_sizes` writes current
  -- ratios back to state, so sizes accumulate drift across close/open
  -- cycles). `reset` tells it to ignore cached state and use init_size
  -- (our original 0.25 per pane).
  require("dapui").open({ reset = true })
  open_bars()
  pin_dapui_sizes()

  -- second install pass after dapui has created its buffers
  vim.schedule(function()
    if not active then return end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then M._install_for_buf(buf) end
    end
    pin_dapui_sizes()
    render_bars()
    -- Seed the dapui-area baseline AFTER the final layout settles, so
    -- the first WinResized (e.g. bufferline tabline appearing) sees a
    -- valid reference point to compare against.
    last_dapui_total_height = compute_dapui_total_height()
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
  help.close()

  -- Close dapui FIRST so dapui's windows tear down into a state we
  -- control. Closing our bars first would let dapui's remaining panes
  -- expand into the freed rows, which dapui then "remembers" and
  -- breaks the next open's layout.
  if dapui_initialized then require("dapui").close() end
  close_bars()
  if vt_initialized then require("nvim-dap-virtual-text").disable() end
  last_dapui_total_height = nil
  if saved_winsep_hl ~= nil then
    pcall(vim.api.nvim_set_hl, 0, "WinSeparator", saved_winsep_hl)
    saved_winsep_hl = nil
  end
end

function M.toggle()
  if active then M.exit() else M.enter() end
end

function M.is_active() return active end

return M
