local h = require("helpers")
local assert_eq = h.assert_eq
local assert_true = h.assert_true
local assert_false = h.assert_false

local mode = require("turbo-debug.mode")
local config = require("turbo-debug.config")

-- Ensure config is initialized with defaults so keyof/render_cbar can read it
config.merge({})

-- Helpers --------------------------------------------------------------------

local function make_bar_win()
  vim.cmd("noautocmd keepalt topleft split")
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(win, 2)
  return win, buf
end

local function cleanup(win)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function line(buf, i)
  return vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1] or ""
end

-- build_control_text -------------------------------------------------------

-- Inline form when key matches first letter case-insensitively.
local text, kcol, kend, icol, iend = mode._test.build_control_text(">", "s", "step", "over")
assert_true(text:find("%(s%)tep") ~= nil, "inline form: (s)tep present")
assert_true(kcol < kend, "inline form: key_col < key_end_col")
assert_true(icol ~= nil and iend ~= nil, "inline form: italic span present")
assert_true(text:sub(icol + 1, iend) == "over", "inline form: italic text is 'over'")

-- Prefix form when key does NOT match first letter.
local text2, _, _, icol2 = mode._test.build_control_text(">", "n", "step", "over")
assert_true(text2:find("%(n%) step") ~= nil, "prefix form: (n) step present")
assert_true(icol2 ~= nil, "prefix form: italic still rendered")

-- No italic when italic param is nil.
local text3, _, _, icol3 = mode._test.build_control_text(">", "c", "continue", nil)
assert_eq(icol3, nil, "no italic span when italic=nil")
assert_true(text3:find("%(c%)ontinue") ~= nil, "no italic: (c)ontinue rendered")

-- keyof ----------------------------------------------------------------------

-- Save any user override then reset to defaults
config.merge({})
assert_eq(mode._test.keyof("continue", "c"), "c", "keyof returns default when unset")

-- Disabled action returns nil
config.merge({ keys = { continue = false } })
assert_eq(mode._test.keyof("continue", "c"), nil, "keyof returns nil when key=false")

-- User override
config.merge({ keys = { continue = "g" } })
assert_eq(mode._test.keyof("continue", "c"), "g", "keyof returns user override")

-- Empty string falls back to default
config.merge({ keys = { continue = "" } })
assert_eq(mode._test.keyof("continue", "c"), "c", "keyof falls back on empty string")

-- Reset config to defaults for subsequent render tests
config.merge({})

-- render_sbar ----------------------------------------------------------------

do
  local win, buf = make_bar_win()
  mode._test.set_bars(win, buf, nil, nil)
  mode._test.render_sbar()
  local count = vim.api.nvim_buf_line_count(buf)
  assert_eq(count, 2, "sbar has exactly 2 lines")
  local sep = line(buf, 0)
  local content = line(buf, 1)
  assert_true(#sep > 0, "sbar separator non-empty")
  assert_true(content:find(" turbo%-debug ") ~= nil, "sbar contains brand text")
  assert_true(content:find("DEBUG") ~= nil, "sbar contains DEBUG chip")
  -- sbar has no click zones
  local zones = mode._test.get_sbar_zones()
  assert_eq(#zones, 0, "sbar has zero click zones")
  mode._test.set_bars(nil, nil, nil, nil)
  cleanup(win)
end

-- render_cbar ----------------------------------------------------------------

do
  local win, buf = make_bar_win()
  vim.api.nvim_win_set_width(win, 120)
  mode._test.set_bars(nil, nil, win, buf)
  mode._test.render_cbar()
  local count = vim.api.nvim_buf_line_count(buf)
  assert_eq(count, 2, "cbar has exactly 2 lines")
  local content = line(buf, 0)
  local sep = line(buf, 1)
  assert_true(#sep > 0, "cbar separator non-empty")
  assert_true(content:find(" help ") ~= nil, "cbar contains 'help' text")
  -- Click zones: at least 5 controls (continue, step_over, step_into, step_out, terminate) + 1 help
  -- When no session, restart is hidden so zone count = 5 + 1 = 6.
  local zones = mode._test.get_cbar_zones()
  assert_true(#zones >= 6, "cbar has at least 6 click zones: " .. #zones)
  mode._test.set_bars(nil, nil, nil, nil)
  cleanup(win)
end

-- overflow fallback: at narrow widths, italic qualifiers are dropped
do
  local win, buf = make_bar_win()
  vim.api.nvim_win_set_width(win, 25)
  mode._test.set_bars(nil, nil, win, buf)
  mode._test.render_cbar()
  local content = line(buf, 0)
  -- italic qualifiers are "over", "into", "out" — on overflow they're omitted.
  -- At width 25 with 5+ controls, there's no way they all fit with italics.
  assert_false(content:find(" over ") or content:find(" into ") or content:find(" out "),
    "overflow: italic qualifiers absent at narrow width")
  mode._test.set_bars(nil, nil, nil, nil)
  cleanup(win)
end

-- disabling step_over reduces zone count
do
  local win, buf = make_bar_win()
  vim.api.nvim_win_set_width(win, 120)
  mode._test.set_bars(nil, nil, win, buf)
  mode._test.render_cbar()
  local default_count = #mode._test.get_cbar_zones()

  config.merge({ keys = { step_over = false } })
  mode._test.render_cbar()
  local disabled_count = #mode._test.get_cbar_zones()
  assert_eq(disabled_count, default_count - 1, "disabling step_over drops one zone")

  config.merge({}) -- reset
  mode._test.set_bars(nil, nil, nil, nil)
  cleanup(win)
end

print("ALL RENDER BAR TESTS PASSED")
