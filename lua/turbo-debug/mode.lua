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
  -- controls (match dapui's own controls-panel defaults)
  play        = "\xee\xab\x98",  -- U+EAD8 debug-start
  pause       = "\xee\xab\x99",  -- U+EAD9 debug-pause
  step_over   = "\xee\xab\x96",  -- U+EAD6 debug-step-over
  step_into   = "\xee\xab\x95",  -- U+EAD5 debug-step-into
  step_out    = "\xee\xab\x94",  -- U+EAD4 debug-step-out
  step_back   = "\xee\xac\xb4",  -- U+EB34 debug-step-back
  restart     = "\xee\xad\x84",  -- U+EB44 debug-restart
  stop        = "\xee\xab\x97",  -- U+EAD7 debug-stop
  disconnect  = "\xee\xab\xb7",  -- U+EAF7 debug-disconnect
  close       = "\xee\xa9\xb6",  -- U+EA76 close

  -- signs
  breakpoint  = "\xee\xa9\xb1",  -- U+EA71 debug-breakpoint
  bp_cond     = "\xee\xaa\x9f",  -- U+EA9F debug-breakpoint-conditional
  bp_rej      = "\xee\xaa\xbe",  -- U+EABE circle-slash
  stackframe  = "\xee\xae\x8b",  -- U+EB8B debug-stackframe
  logpoint    = "\xee\xaf\xa4",  -- U+EBE4 debug-breakpoint-log

  -- pane titles
  scopes      = "\xee\xaa\x8f",  -- U+EA8F variable-group
  watches     = "\xee\xa9\xb0",  -- U+EA70 eye
  stacks      = "\xee\xae\x83",  -- U+EB83 list-tree
  terminal    = "\xee\xaa\x85",  -- U+EA85 terminal
  chevron     = "\xee\xaa\xb6",  -- U+EAB6 chevron-right

  -- debug badge (bug-in-circle)
  debug_alt   = "\xee\xae\x91",  -- U+EB91 debug-alt

  -- misc
  ip_left     = "\xf0\x9f\x91\x88",  -- 👈 backhand index pointing left (U+1F448)
  divider     = "\xc2\xb7",          -- · middle dot
  ellipsis    = "\xe2\x80\xa6",      -- … horizontal ellipsis
  wrap_mark   = "\xe2\x86\xb3",      -- ↳ downward-arrow-with-tip-rightwards
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
      position = "bottom",
      size = 12,
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
  hl(0, "TurboDebugBarCtrl",        { default = true, link = "Function" })
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

-- ─── global control buttons (referenced by bar winbar expression) ───────────

_G.turbo_debug_continue   = function() M.actions().continue() end
_G.turbo_debug_step_over  = function() require("dap").step_over() end
_G.turbo_debug_step_into  = function() require("dap").step_into() end
_G.turbo_debug_step_out   = function() require("dap").step_out() end
_G.turbo_debug_restart    = function() require("dap").restart() end
_G.turbo_debug_terminate  = function() M.actions().terminate() end
_G.turbo_debug_toggle     = function() M.toggle() end

function _G.turbo_debug_bar()
  local dap_ok, dap = pcall(require, "dap")
  local state, state_hl
  if not dap_ok then
    state, state_hl = "READY", "TurboDebugBarReady"
  else
    local s = dap.session()
    if not s then
      state, state_hl = "READY", "TurboDebugBarReady"
    elseif s.stopped_thread_id then
      state, state_hl = "PAUSED", "TurboDebugBarPaused"
    else
      state, state_hl = "RUNNING", "TurboDebugBarRunning"
    end
  end

  local parts = {
    "%#" .. state_hl .. "# " .. ICON.debug_alt .. " " .. state .. " %*",
    "  ",
    "%#TurboDebugBarCtrl#",
    "%@v:lua.turbo_debug_continue@  " .. ICON.play       .. "  %X",
    "%@v:lua.turbo_debug_step_over@  " .. ICON.step_over .. "  %X",
    "%@v:lua.turbo_debug_step_into@  " .. ICON.step_into .. "  %X",
    "%@v:lua.turbo_debug_step_out@  "  .. ICON.step_out  .. "  %X",
    "%@v:lua.turbo_debug_restart@  "   .. ICON.restart   .. "  %X",
    "%@v:lua.turbo_debug_terminate@  " .. ICON.stop      .. "  %X",
    "%@v:lua.turbo_debug_toggle@  "    .. ICON.close     .. "  %X",
    "%*",
    " %=",
    "%#TurboDebugBarStatus#%{v:lua.require'dap'.status()}%*",
    "  %l:%c ",
  }
  return table.concat(parts, "")
end

-- ─── floating control bar ───────────────────────────────────────────────────

local function bar_position()
  -- sit one row above the statusline; statusline is at (lines - cmdheight - 1).
  -- Our bar goes at (lines - cmdheight - 2). If laststatus == 0 there's no
  -- statusline, so sit at the bottom (lines - cmdheight - 1).
  local row
  if vim.o.laststatus > 0 then
    row = vim.o.lines - vim.o.cmdheight - 2
  else
    row = vim.o.lines - vim.o.cmdheight - 1
  end
  if row < 0 then row = 0 end
  return {
    relative  = "editor",
    row       = row,
    col       = 0,
    width     = vim.o.columns,
    height    = 1,
    style     = "minimal",
    border    = "none",
    focusable = false,
    noautocmd = true,
    zindex    = 50,
  }
end

local function open_bar()
  if bar_win and vim.api.nvim_win_is_valid(bar_win) then return end
  bar_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[bar_buf].bufhidden = "wipe"
  bar_win = vim.api.nvim_open_win(bar_buf, false, bar_position())
  vim.wo[bar_win].winbar = "%!v:lua.turbo_debug_bar()"
  vim.wo[bar_win].winhighlight = "Normal:TurboDebugBar,WinBar:TurboDebugBar,WinBarNC:TurboDebugBar"
  vim.wo[bar_win].winfixheight = true
  vim.wo[bar_win].list = false
  vim.wo[bar_win].number = false
  vim.wo[bar_win].relativenumber = false
  vim.wo[bar_win].signcolumn = "no"
end

local function close_bar()
  if bar_win and vim.api.nvim_win_is_valid(bar_win) then
    pcall(vim.api.nvim_win_close, bar_win, true)
  end
  bar_win, bar_buf = nil, nil
end

local function reposition_bar()
  if bar_win and vim.api.nvim_win_is_valid(bar_win) then
    pcall(vim.api.nvim_win_set_config, bar_win, bar_position())
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

  -- IP marker: paired arrows. Gutter sign ▶ + EOL vtext ◀ REASON flanking the
  -- paused line.
  local ip_ns = vim.api.nvim_create_namespace("turbo-debug.ip")
  local function clear_ip()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, ip_ns, 0, -1)
      end
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

  -- winbar titles on dapui panes (Codicons, byte-escaped)
  local titles = {
    dapui_scopes      = " " .. ICON.scopes     .. " Scopes",
    dapui_watches     = " " .. ICON.watches    .. " Watches",
    dapui_stacks      = " " .. ICON.stacks     .. " Call Stack",
    dapui_breakpoints = " " .. ICON.breakpoint .. " Breakpoints",
    dapui_console     = " " .. ICON.terminal   .. " Console",
    ["dap-repl"]      = " " .. ICON.chevron    .. " REPL",
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
  local acts = setup_actions()
  local ft = vim.bo[buf].filetype or ""
  local is_dapui = ft:match("^dapui_") or ft == "dap-repl"
  installed[buf] = installed[buf] or {}
  for name, key in pairs(config.opts.keys) do
    if key and acts[name] and not installed[buf][name] then
      -- yield d/r to dapui's native remove/repl inside its own panes
      if not (is_dapui and (name == "step_into" or name == "step_out")) then
        local prev_n = find_buf_mapping(buf, key, "n")
        local prev_v = visual_actions[name] and find_buf_mapping(buf, key, "v") or nil
        local opts = { buffer = buf, silent = true, nowait = true, desc = "turbo-debug: " .. name }
        pcall(vim.keymap.set, "n", key, acts[name], opts)
        if visual_actions[name] then
          pcall(vim.keymap.set, "v", key, acts[name], opts)
        end
        installed[buf][name] = { key = key, prev_n = prev_n, prev_v = prev_v }
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
  vim.wo[active_win].winbar = "%#TurboDebugWinbar# " .. ICON.debug_alt .. " DEBUG %* " .. ICON.divider .. " %f"
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
