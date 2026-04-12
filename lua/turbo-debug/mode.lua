local config = require("turbo-debug.config")
local help = require("turbo-debug.help")

local M = {}

local active = false
local active_win = nil
local saved_winbar = nil
local saved_statusline = nil
local saved_laststatus = nil

-- installed[buf][name] = { key = lhs, prev_n = <prev n-mode map>, prev_v = <prev v-mode map> }
local installed = {}

local dapui_initialized = false
local vt_initialized = false

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
  hl(0, "TurboDebugSLState",        { default = true, link = "DiagnosticError" })
  hl(0, "TurboDebugSLCtrl",         { default = true, link = "Function" })
  hl(0, "TurboDebugSLStatus",       { default = true, link = "Comment" })
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

-- ─── global control buttons (used by the statusline) ────────────────────────

_G.turbo_debug_continue   = function() M.actions().continue() end
_G.turbo_debug_step_over  = function() require("dap").step_over() end
_G.turbo_debug_step_into  = function() require("dap").step_into() end
_G.turbo_debug_step_out   = function() require("dap").step_out() end
_G.turbo_debug_restart    = function() require("dap").restart() end
_G.turbo_debug_terminate  = function() require("dap").terminate() end
_G.turbo_debug_toggle     = function() M.toggle() end

function _G.turbo_debug_statusline()
  local dap_ok, dap = pcall(require, "dap")
  local state, state_hl
  if not dap_ok then
    state, state_hl = "READY", "TurboDebugSLStatus"
  else
    local s = dap.session()
    if not s then
      state, state_hl = "READY", "TurboDebugSLStatus"
    elseif s.stopped_thread_id then
      state, state_hl = "PAUSED", "TurboDebugSLState"
    else
      state, state_hl = "RUNNING", "TurboDebugSLCtrl"
    end
  end

  -- ● state, then 6 clickable controls, then dap progress text (right-aligned)
  local parts = {
    "%#" .. state_hl .. "# \xe2\x97\x8f " .. state .. " %*",
    "  ",
    "%#TurboDebugSLCtrl#",
    "%@v:lua.turbo_debug_continue@  \xe2\x96\xb6  %X",   -- ▶ continue
    "%@v:lua.turbo_debug_step_over@  \xe2\x87\x92  %X",  -- ⇒ step over
    "%@v:lua.turbo_debug_step_into@  \xe2\xa4\x93  %X",  -- ⤓ step into
    "%@v:lua.turbo_debug_step_out@  \xe2\xa4\x92  %X",   -- ⤒ step out
    "%@v:lua.turbo_debug_restart@  \xe2\x86\xbb  %X",    -- ↻ restart
    "%@v:lua.turbo_debug_terminate@  \xe2\x96\xa0  %X",  -- ■ terminate
    "%@v:lua.turbo_debug_toggle@  \xe2\x8a\x97  %X",     -- ⊗ exit debug mode
    "%*",
    " %=",
    "%#TurboDebugSLStatus#%{v:lua.require'dap'.status()}%*",
    "  %l:%c ",
  }
  return table.concat(parts, "")
end

-- ─── dap-ui setup ────────────────────────────────────────────────────────────

local function set_dapui_window_opts(win)
  -- dapui elements render long single-line values (e.g. register dumps) that
  -- bleed into adjacent windows when wrap is on. Force-disable wrap and
  -- horizontal-scroll padding so values stay inside the pane.
  if vim.api.nvim_win_is_valid(win) then
    vim.wo[win].wrap = false
    vim.wo[win].sidescrolloff = 0
    vim.wo[win].linebreak = false
    vim.wo[win].cursorline = true
  end
end

local function ensure_dapui()
  if dapui_initialized then return end
  dapui_initialized = true
  local dapui_opts = vim.deepcopy(config.opts.dapui)
  if not dapui_opts.layouts then dapui_opts.layouts = build_default_layouts() end
  require("dapui").setup(dapui_opts)

  local dap = require("dap")
  dap.listeners.after.event_initialized["turbo-debug"] = function()
    require("dapui").open()
  end

  -- K = hover during a live dap session (works globally, not just modally)
  dap.listeners.after.event_initialized["turbo-debug-hover"] = function()
    vim.keymap.set("n", "K", function()
      require("dap.ui.widgets").hover(nil, { border = "rounded" })
    end, { silent = true, desc = "DAP hover" })
  end
  dap.listeners.after.event_terminated["turbo-debug-hover"] = function()
    pcall(vim.keymap.del, "n", "K")
  end

  -- Console redraws: dapui's console buffer updates on event_output but
  -- nvim doesn't always repaint the window until focus changes. Force a
  -- schedule-wrapped redraw so output appears live.
  dap.listeners.after.event_output["turbo-debug-redraw"] = vim.schedule_wrap(function()
    pcall(vim.cmd.redraw)
  end)

  -- IP marker: paired-arrow design.
  --   gutter:  ▶  (points RIGHT at the line from the sign column)
  --   eol:     ◀  (points LEFT at the line from the end of content)
  -- The uppercase reason (STEP / BREAKPOINT / EXCEPTION / PAUSE / ENTRY)
  -- renders in bold TurboDebugIPReason so it jumps off the screen.
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
          { "  \xe2\x97\x80  ", "DapStopped" },   -- ◀
          { reason,             "TurboDebugIPReason" },
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

  -- dapui winbar titles + window options (wrap=false to stop the register
  -- overflow bug). Apply on FileType so we catch every pane dapui creates.
  local titles = {
    dapui_scopes      = " \xe2\x97\x86 Scopes",
    dapui_watches     = " \xe2\x97\x89 Watches",
    dapui_stacks      = " \xe2\x89\xa1 Call Stack",
    dapui_breakpoints = " \xe2\x97\x8f Breakpoints",
    dapui_console     = " \xe2\x9d\xaf Console",
    ["dap-repl"]      = " \xe2\x9d\xaf_ REPL",
  }
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "dapui_*", "dap-repl" },
    callback = function(args)
      local ft = vim.bo[args.buf].filetype
      local title = titles[ft]
      vim.schedule(function()
        local win = vim.fn.bufwinid(args.buf)
        if win ~= -1 then
          if title then vim.wo[win].winbar = title end
          set_dapui_window_opts(win)
        end
        -- also (re-)install modal keys on this dapui buffer — BufEnter may
        -- not fire at create time and we want the keys ready the moment
        -- the user clicks in.
        if active then M._install_for_buf(args.buf) end
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
    -- no config → fall back to normal continue (which will prompt / error)
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
  -- if no session yet, a step key starts the session with stop-on-entry —
  -- matches the Turbo Pascal "just press a key to start stepping" vibe.
  if require("dap").session() then
    step_fn()
  else
    smart_continue()
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
    terminate     = function()
      dap.terminate()
      if config.opts.quit_exits_mode then M.exit() end
    end,
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
  installed[buf] = installed[buf] or {}
  for name, key in pairs(config.opts.keys) do
    if key and acts[name] and not installed[buf][name] then
      local prev_n = find_buf_mapping(buf, key, "n")
      local prev_v = visual_actions[name] and find_buf_mapping(buf, key, "v") or nil
      local opts = { buffer = buf, silent = true, desc = "turbo-debug: " .. name }
      if name == "continue" then opts.nowait = true end
      pcall(vim.keymap.set, "n", key, acts[name], opts)
      if visual_actions[name] then
        pcall(vim.keymap.set, "v", key, acts[name], opts)
      end
      installed[buf][name] = { key = key, prev_n = prev_n, prev_v = prev_v }
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

-- ─── chrome: per-source-window winbar badge + global statusline controls ──

local function set_debug_chrome()
  active_win = vim.api.nvim_get_current_win()
  saved_winbar = vim.wo[active_win].winbar
  vim.wo[active_win].winbar = "%#TurboDebugWinbar# \xe2\x97\x8f DEBUG %* %f"

  saved_statusline = vim.o.statusline
  saved_laststatus = vim.o.laststatus
  vim.o.laststatus = 3  -- one global statusline
  vim.o.statusline = "%!v:lua.turbo_debug_statusline()"
end

local function clear_debug_chrome()
  if active_win and vim.api.nvim_win_is_valid(active_win) then
    vim.wo[active_win].winbar = saved_winbar or ""
  end
  active_win = nil
  saved_winbar = nil

  if saved_statusline ~= nil then vim.o.statusline = saved_statusline end
  if saved_laststatus ~= nil then vim.o.laststatus = saved_laststatus end
  saved_statusline = nil
  saved_laststatus = nil
end

-- ─── public API ─────────────────────────────────────────────────────────────

function M.enter()
  if active then return end
  active = true
  define_highlights()
  setup_actions()

  vim.api.nvim_create_augroup("TurboDebugModalKeys", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = "TurboDebugModalKeys",
    callback = function(args)
      if active then M._install_for_buf(args.buf) end
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M._install_for_buf(buf) end
  end

  set_debug_chrome()
  ensure_dapui()
  require("dapui").open()

  -- second install pass after dapui has created its buffers, since BufEnter
  -- doesn't always fire for windows that were opened without focus-change.
  vim.schedule(function()
    if not active then return end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then M._install_for_buf(buf) end
    end
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

  if dapui_initialized then require("dapui").close() end
  if vt_initialized then require("nvim-dap-virtual-text").disable() end
end

function M.toggle()
  if active then M.exit() else M.enter() end
end

function M.is_active() return active end

return M
