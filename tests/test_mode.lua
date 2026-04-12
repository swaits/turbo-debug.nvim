local assert_eq = require("helpers").assert_eq
local td = require("turbo-debug")

local function has_buf_map(key)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
    if m.lhs == key then return true end
  end
  return false
end

-- starts inactive
assert_eq(td.active(), false, "starts inactive")

-- toggle enters debug mode
td.toggle()
assert_eq(td.active(), true, "active after toggle")

-- all modal keymaps are set (including breakpoint keys)
for _, key in ipairs({ "c", "s", "d", "r", "q", "x", "X", "D" }) do
  assert_eq(has_buf_map(key), true, key .. " key mapped")
end

-- toggle exits debug mode
td.toggle()
assert_eq(td.active(), false, "inactive after second toggle")

-- all modal keymaps are removed
for _, key in ipairs({ "c", "s", "d", "r", "q", "x", "X", "D" }) do
  assert_eq(has_buf_map(key), false, key .. " key removed")
end

-- double exit is safe
td.toggle() -- enter
td.toggle() -- exit
td.toggle() -- enter
td.toggle() -- exit
assert_eq(td.active(), false, "stable after multiple toggles")

-- verify no leaked keymaps after rapid toggling
for _, key in ipairs({ "c", "s", "d", "r", "q", "x", "X", "D" }) do
  assert_eq(has_buf_map(key), false, key .. " clean after rapid toggle")
end

print("ALL MODE TESTS PASSED")
