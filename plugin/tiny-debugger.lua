-- tiny-debugger.nvim — entry point

-- require Neovim 0.12+
if vim.fn.has("nvim-0.12") ~= 1 then
  vim.notify("tiny-debugger.nvim requires Neovim >= 0.12", vim.log.levels.ERROR)
  return
end

-- load dependencies via vim.pack
vim.pack.add({ "mfussenegger/nvim-dap" })
vim.pack.add({ "rcarriga/nvim-dap-ui" })
vim.pack.add({ "nvim-neotest/nvim-nio" })
vim.pack.add({ "theHamsta/nvim-dap-virtual-text" })
vim.pack.add({ "Weissle/persistent-breakpoints.nvim" })

-- initialize with defaults (user can call setup() to override)
require("tiny-debugger").setup()

-- toggle debug mode
vim.keymap.set("n", "<leader>d", function()
  require("tiny-debugger").toggle()
end, { silent = true, desc = "tiny-debugger: toggle debug mode" })
