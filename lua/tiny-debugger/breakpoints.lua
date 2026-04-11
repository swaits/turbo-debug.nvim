local config = require("tiny-debugger.config")

local M = {}

local initialized = false

function M.setup()
  if initialized then return end
  initialized = true

  require("persistent-breakpoints").setup({
    load_breakpoints_event = { "BufReadPost" },
  })

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
end

return M
