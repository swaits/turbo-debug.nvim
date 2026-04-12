local assert_eq = require("helpers").assert_eq
local td = require("tiny-debugger")

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

-- keymaps are set
for _, key in ipairs({ "c", "s", "d", "r", "q" }) do
  assert_eq(has_buf_map(key), true, key .. " key mapped")
end

-- toggle exits debug mode
td.toggle()
assert_eq(td.active(), false, "inactive after second toggle")

-- keymaps are removed
for _, key in ipairs({ "c", "s", "d", "r", "q" }) do
  assert_eq(has_buf_map(key), false, key .. " key removed")
end

print("ALL MODE TESTS PASSED")
