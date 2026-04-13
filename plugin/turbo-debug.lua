-- turbo-debug.nvim — entry point

if vim.fn.has("nvim-0.12") ~= 1 then
  vim.notify("turbo-debug.nvim requires Neovim >= 0.12", vim.log.levels.ERROR)
  return
end

vim.pack.add({ "mfussenegger/nvim-dap" })
vim.pack.add({ "rcarriga/nvim-dap-ui" })
vim.pack.add({ "nvim-neotest/nvim-nio" })
vim.pack.add({ "theHamsta/nvim-dap-virtual-text" })
vim.pack.add({ "Weissle/persistent-breakpoints.nvim" })

-- register which-key group if available
pcall(function()
  require("which-key").add({ { "<leader>d", group = "debug" } })
end)

-- Deferred auto-setup. Must be deferred (not called synchronously) because
-- the vim.pack.add calls above might not have finished registering the
-- dep modules in runtimepath by the time this script's top-level runs —
-- a synchronous `require('persistent-breakpoints.api')` inside setup would
-- crash with "module not found". vim.schedule guarantees we run AFTER the
-- current event loop tick, at which point pack has finalized the paths.
--
-- If the user calls setup({...}) themselves (typically from init.lua after
-- vim.pack.add), `M._setup_called` flips true and this deferred call
-- becomes a no-op — otherwise we'd overwrite their user opts with defaults.
vim.schedule(function()
  local td = require("turbo-debug")
  if td._setup_called then return end
  pcall(td.setup)
end)
