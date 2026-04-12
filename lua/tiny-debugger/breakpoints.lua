local config = require("tiny-debugger.config")

local M = {}

local initialized = false

function M.setup()
  if initialized then return end
  initialized = true

  require("persistent-breakpoints").setup({
    load_breakpoints_event = { "BufReadPost" },
  })

  -- sign highlights (default = true so colorschemes can override)
  vim.api.nvim_set_hl(0, "DapBreakpoint", { default = true, fg = "#e06c75" })
  vim.api.nvim_set_hl(0, "DapBreakpointCondition", { default = true, fg = "#e5c07b" })
  vim.api.nvim_set_hl(0, "DapBreakpointRejected", { default = true, fg = "#5c6370" })
  vim.api.nvim_set_hl(0, "DapStopped", { default = true, fg = "#98c379" })
  vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, bg = "#2e3b2e" })
  vim.api.nvim_set_hl(0, "DapLogPoint", { default = true, fg = "#61afef" })

  vim.fn.sign_define("DapBreakpoint", { text = "🔴", texthl = "DapBreakpoint" })
  vim.fn.sign_define("DapBreakpointCondition", { text = "🟡", texthl = "DapBreakpointCondition" })
  vim.fn.sign_define("DapBreakpointRejected", { text = "⭕", texthl = "DapBreakpointRejected" })
  vim.fn.sign_define("DapStopped", { text = "▶️", texthl = "DapStopped", linehl = "DapStoppedLine" })
  vim.fn.sign_define("DapLogPoint", { text = "📝", texthl = "DapLogPoint" })

  -- global mappings (work outside debug mode)
  local keys = config.opts.keys
  local pb = require("persistent-breakpoints.api")
  local bindings = {
    { keys.breakpoint, pb.toggle_breakpoint, "toggle breakpoint" },
    { keys.cond_breakpoint, pb.set_conditional_breakpoint, "conditional breakpoint" },
    { keys.clear_breakpoints, pb.clear_all_breakpoints, "clear all breakpoints" },
  }
  for _, b in ipairs(bindings) do
    if b[1] then
      vim.keymap.set("n", b[1], b[2], { silent = true, desc = "tiny-debugger: " .. b[3] })
    end
  end
end

return M
