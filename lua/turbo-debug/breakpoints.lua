local config = require("turbo-debug.config")

local M = {}

-- This function is idempotent — every operation inside is safe to re-run.
-- That property matters because turbo-debug.setup() can get called twice in
-- practice:
--   (1) Deferred auto-setup from plugin/turbo-debug.lua, which runs after
--       vim.pack.add has finished registering all deps in runtimepath. The
--       defer is necessary — calling setup synchronously during
--       vim.pack.add would try to `require('persistent-breakpoints.api')`
--       before the plugin's lua/ directory is on the runtimepath and
--       crash with "module not found".
--   (2) User's explicit setup({...}) in their init.lua with config
--       overrides. It runs immediately (before the deferred auto-setup).
--
-- Previously a single `initialized` flag guarded this function so it only
-- ran once. That guard was fragile: if the first call errored partway
-- (case above), the flag was set but the setup was incomplete, and the
-- second call skipped the retry. We now let every call do its full work;
-- persistent-breakpoints.setup re-reads its bps file, sign_define overrides
-- a previous definition, nvim_set_hl overrides a previous link, and
-- vim.keymap.set overrides a previous binding.
function M.setup()
  require("persistent-breakpoints").setup({
    load_breakpoints_event = { "BufReadPost" },
  })

  -- link sign highlights to standard diagnostic groups so they pick up the
  -- user's colorscheme instead of hardcoding hex colors.
  vim.api.nvim_set_hl(0, "DapBreakpoint", { default = true, link = "DiagnosticError" })
  vim.api.nvim_set_hl(0, "DapBreakpointCondition", { default = true, link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "DapBreakpointRejected", { default = true, link = "DiagnosticHint" })
  vim.api.nvim_set_hl(0, "DapStopped", { default = true, link = "DiagnosticOk" })
  vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Search" })
  vim.api.nvim_set_hl(0, "DapLogPoint", { default = true, link = "DiagnosticInfo" })

  -- Gutter signs: colorful emoji for instant recognition. Modern terminals
  -- (Ghostty, Kitty, WezTerm, iTerm) render these full-color.
  --   🔴 U+1F534 large red circle       = breakpoint
  --   🟡 U+1F7E1 large yellow circle     = conditional breakpoint
  --   ⭕ U+2B55  heavy large circle      = rejected breakpoint
  --   👉 U+1F449 backhand pointing right = current execution line (IP)
  --   📝 U+1F4DD memo                    = log point
  local signs = {
    { "DapBreakpoint",          "\xf0\x9f\x94\xb4" },
    { "DapBreakpointCondition", "\xf0\x9f\x9f\xa1" },
    { "DapBreakpointRejected",  "\xe2\xad\x95"     },
    { "DapStopped",             "\xf0\x9f\x91\x89", { linehl = "DapStoppedLine" } },
    { "DapLogPoint",            "\xf0\x9f\x93\x9d" },
  }
  for _, s in ipairs(signs) do
    local spec = { text = s[2], texthl = s[1], numhl = s[1] }
    if s[3] then for k, v in pairs(s[3]) do spec[k] = v end end
    vim.fn.sign_define(s[1], spec)
  end

  -- unobtrusive inline virtual text: italic, comment-colored
  vim.api.nvim_set_hl(0, "NvimDapVirtualText", { default = true, link = "Comment", italic = true })
  vim.api.nvim_set_hl(0, "NvimDapVirtualTextChanged", { default = true, link = "DiagnosticWarn", italic = true })
  vim.api.nvim_set_hl(0, "NvimDapVirtualTextError", { default = true, link = "DiagnosticError", italic = true })
  vim.api.nvim_set_hl(0, "NvimDapVirtualTextInfo", { default = true, link = "DiagnosticInfo", italic = true })

  -- turbo-debug's own UI groups (help float, active-pane borders, winbar badge)
  vim.api.nvim_set_hl(0, "TurboDebugHelpBrand",       { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "TurboDebugHelpTagline",     { default = true, link = "Comment", italic = true })
  vim.api.nvim_set_hl(0, "TurboDebugHelpSection",     { default = true, link = "Function" })
  vim.api.nvim_set_hl(0, "TurboDebugHelpSectionIcon", { default = true, link = "Constant" })
  vim.api.nvim_set_hl(0, "TurboDebugHelpKey",         { default = true, link = "Special" })
  vim.api.nvim_set_hl(0, "TurboDebugHelpParen",       { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "TurboDebugCtrlButton",      { default = true, link = "Function" })
  vim.api.nvim_set_hl(0, "TurboDebugCtrlMuted",       { default = true, link = "Comment" })

  -- derived highlight: the IP "reason" vtext (STEP / BREAKPOINT / EXCEPTION /
  -- PAUSE / etc.) — bold + reverse + WarningMsg color so it renders as an
  -- inverted-color badge that absolutely demands attention. nvim_set_hl
  -- can't combine link + bold, so copy attrs explicitly and re-apply on
  -- ColorScheme so theme switches don't blank it out.
  local function apply_ip_reason_hl()
    local ok, src = pcall(vim.api.nvim_get_hl, 0, { name = "WarningMsg", link = false })
    if not ok or not src or not src.fg then return end
    vim.api.nvim_set_hl(0, "TurboDebugIPReason", {
      fg = src.fg, bg = src.bg, bold = true, reverse = true, default = true,
    })
  end
  apply_ip_reason_hl()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("TurboDebugColors", { clear = true }),
    callback = apply_ip_reason_hl,
  })

  -- global mappings (work outside debug mode)
  local gk = config.opts.global_keys
  local pb = require("persistent-breakpoints.api")
  local bindings = {
    { gk.breakpoint, pb.toggle_breakpoint, "Toggle breakpoint" },
    { gk.cond_breakpoint, pb.set_conditional_breakpoint, "Conditional breakpoint" },
    { gk.clear_breakpoints, pb.clear_all_breakpoints, "Clear all breakpoints" },
  }
  for _, b in ipairs(bindings) do
    if b[1] then
      vim.keymap.set("n", b[1], b[2], { silent = true, desc = b[3] })
    end
  end
end

return M
