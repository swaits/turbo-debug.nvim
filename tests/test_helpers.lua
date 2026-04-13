-- Unit tests for the helpers introduced during cleanup refactor.
-- Exercises helpers indirectly via observable side effects on bar/pane state.

local h = require("helpers")
local assert_eq = h.assert_eq
local assert_true = h.assert_true
local assert_false = h.assert_false

local mode = require("turbo-debug.mode")
local config = require("turbo-debug.config")
config.merge({})

-- keyof ---------------------------------------------------------------------
-- Reset, then exercise the three return paths.
config.merge({})
assert_eq(mode._test.keyof("continue", "c"), "c", "default key")
config.merge({ keys = { continue = "n" } })
assert_eq(mode._test.keyof("continue", "c"), "n", "user override")
config.merge({ keys = { continue = false } })
assert_eq(mode._test.keyof("continue", "c"), nil, "disabled returns nil")
config.merge({})

-- source_window -------------------------------------------------------------
-- Skips bars/dapui-panes; returns a source window when one exists.
do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "lua"
  vim.api.nvim_set_current_buf(buf)
  local w = mode._test.source_window()
  assert_true(w ~= nil, "source_window finds lua buffer")
end

do
  -- Switch current to a dapui-pane filetype; source_window should still
  -- find another source window if one exists.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "dapui_scopes"
  vim.cmd("split")
  vim.api.nvim_set_current_buf(buf)
  local w = mode._test.source_window()
  if w then
    local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
    assert_false(ft:match("^dapui_"), "source_window skips dapui_* filetypes")
    assert_true(ft ~= "dap-repl", "source_window skips dap-repl")
    assert_true(ft ~= "TurboDebugBar", "source_window skips TurboDebugBar")
  end
end

print("ALL HELPER TESTS PASSED")
