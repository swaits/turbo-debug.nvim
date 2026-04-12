local config = require("tiny-debugger.config")

local M = {}

local initialized = false

function M.setup()
  if initialized then return end
  initialized = true

  require("persistent-breakpoints").setup({
    load_breakpoints_event = { "BufReadPost" },
  })

  -- sign highlights
  vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#e06c75" })
  vim.api.nvim_set_hl(0, "DapBreakpointCondition", { fg = "#e5c07b" })
  vim.api.nvim_set_hl(0, "DapBreakpointRejected", { fg = "#5c6370" })
  vim.api.nvim_set_hl(0, "DapStopped", { fg = "#98c379" })
  vim.api.nvim_set_hl(0, "DapStoppedLine", { bg = "#2e3b2e" })
  vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#61afef" })

  -- gutter signs
  vim.fn.sign_define("DapBreakpoint", { text = "🔴", texthl = "DapBreakpoint" })
  vim.fn.sign_define("DapBreakpointCondition", { text = "🟡", texthl = "DapBreakpointCondition" })
  vim.fn.sign_define("DapBreakpointRejected", { text = "⭕", texthl = "DapBreakpointRejected" })
  vim.fn.sign_define("DapStopped", { text = "▶️", texthl = "DapStopped", linehl = "DapStoppedLine" })
  vim.fn.sign_define("DapLogPoint", { text = "📝", texthl = "DapLogPoint" })

  -- global mappings — these work outside debug mode
  local keys = config.opts.keys
  if keys.breakpoint then
    vim.keymap.set("n", keys.breakpoint, function()
      require("persistent-breakpoints.api").toggle_breakpoint()
    end, { silent = true, desc = "tiny-debugger: toggle breakpoint" })
  end
  if keys.cond_breakpoint then
    vim.keymap.set("n", keys.cond_breakpoint, function()
      require("persistent-breakpoints.api").set_conditional_breakpoint()
    end, { silent = true, desc = "tiny-debugger: conditional breakpoint" })
  end
  if keys.clear_breakpoints then
    vim.keymap.set("n", keys.clear_breakpoints, function()
      require("persistent-breakpoints.api").clear_all_breakpoints()
    end, { silent = true, desc = "tiny-debugger: clear all breakpoints" })
  end
end

return M
