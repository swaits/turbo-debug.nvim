local config = require("turbo-debug.config")

local M = {}

local initialized = false

function M.setup()
  if initialized then return end
  initialized = true

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

  -- Gutter signs: Nerd Font Codicons (byte-escaped for tool-pipeline safety).
  -- The DapStopped IP sign is an emoji 👉 (backhand index pointing right,
  -- U+1F449) that literally points AT the paused line from the left. Pairs
  -- with the 👈 emoji in the EOL virtual text (mode.lua) — both fingers
  -- point at the current line from opposite sides, unmistakable.
  --
  --   nf-cod-debug-breakpoint              = U+EA71 ""
  --   nf-cod-debug-breakpoint-conditional  = U+EA9F ""
  --   nf-cod-circle-slash                  = U+EABE ""
  --   nf-cod-debug-breakpoint-log          = U+EBE4 ""
  vim.fn.sign_define("DapBreakpoint",          { text = "\xee\xa9\xb1", texthl = "DapBreakpoint",          numhl = "DapBreakpoint" })
  vim.fn.sign_define("DapBreakpointCondition", { text = "\xee\xaa\x9f", texthl = "DapBreakpointCondition", numhl = "DapBreakpointCondition" })
  vim.fn.sign_define("DapBreakpointRejected",  { text = "\xee\xaa\xbe", texthl = "DapBreakpointRejected",  numhl = "DapBreakpointRejected" })
  vim.fn.sign_define("DapStopped",             { text = "\xf0\x9f\x91\x89", texthl = "DapStopped", linehl = "DapStoppedLine", numhl = "DapStopped" })
  vim.fn.sign_define("DapLogPoint",            { text = "\xee\xaf\xa4", texthl = "DapLogPoint",            numhl = "DapLogPoint" })

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
  -- PAUSE / etc.) — bold + the WarningMsg color so it jumps off the screen.
  -- nvim_set_hl can't combine link + bold, so copy attrs explicitly and
  -- re-apply on ColorScheme so theme switches don't blank it out.
  local function apply_ip_reason_hl()
    local ok, src = pcall(vim.api.nvim_get_hl, 0, { name = "WarningMsg", link = false })
    if not ok or not src or not src.fg then return end
    vim.api.nvim_set_hl(0, "TurboDebugIPReason", {
      fg = src.fg, bg = src.bg, bold = true, default = true,
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
