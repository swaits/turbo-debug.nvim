local h = require("helpers")
local assert_eq = h.assert_eq
local assert_true = h.assert_true

local mode = require("turbo-debug.mode")
local config = require("turbo-debug.config")
config.merge({})

-- Invoke define_highlights via the _test hook.
mode._test.define_highlights()

-- The three ColorScheme augroups must exist with at least one autocmd each.
local function group_has_colorscheme_autocmd(group_name)
  local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = group_name, event = "ColorScheme" })
  return ok and autocmds and #autocmds >= 1
end

assert_true(group_has_colorscheme_autocmd("TurboDebugBarItalicHL"), "italic augroup has ColorScheme autocmd")
assert_true(group_has_colorscheme_autocmd("TurboDebugBarKeyHL"), "key augroup has ColorScheme autocmd")
assert_true(group_has_colorscheme_autocmd("TurboDebugBarSepHL"), "sep augroup has ColorScheme autocmd")

-- The highlight groups must exist after define_highlights.
local function hl_exists(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
  return ok and hl ~= nil and next(hl) ~= nil
end

assert_true(hl_exists("TurboDebugBarItalic"), "TurboDebugBarItalic exists")
assert_true(hl_exists("TurboDebugBarKey"), "TurboDebugBarKey exists")
assert_true(hl_exists("TurboDebugBarSeparator"), "TurboDebugBarSeparator exists")
assert_true(hl_exists("TurboDebugBar"), "TurboDebugBar exists")
assert_true(hl_exists("TurboDebugBarBrand"), "TurboDebugBarBrand exists")

-- Fire ColorScheme event; the callbacks should re-apply highlights (idempotent).
vim.cmd("doautocmd ColorScheme")
assert_true(hl_exists("TurboDebugBarItalic"), "TurboDebugBarItalic still exists after ColorScheme")
assert_true(hl_exists("TurboDebugBarKey"), "TurboDebugBarKey still exists after ColorScheme")
assert_true(hl_exists("TurboDebugBarSeparator"), "TurboDebugBarSeparator still exists after ColorScheme")

print("ALL HIGHLIGHT CS TESTS PASSED")
