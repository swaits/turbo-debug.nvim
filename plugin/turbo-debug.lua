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

-- setup immediately (idempotent — user can call setup() again with overrides)
require("turbo-debug").setup()
