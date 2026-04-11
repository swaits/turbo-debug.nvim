-- tests for debug mode enter/exit
local td = require("tiny-debugger")
local mode = require("tiny-debugger.mode")

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("FAIL: %s — expected %s, got %s", msg, vim.inspect(b), vim.inspect(a)))
  end
end

local function has_buf_map(key)
  local maps = vim.api.nvim_buf_get_keymap(0, "n")
  for _, m in ipairs(maps) do
    if m.lhs == key then return true end
  end
  return false
end

-- test 1: starts inactive
assert_eq(td.active(), false, "starts inactive")

-- test 2: toggle enters debug mode
td.toggle()
assert_eq(td.active(), true, "active after toggle")

-- test 3: keymaps are set
assert_eq(has_buf_map("c"), true, "continue key mapped")
assert_eq(has_buf_map("s"), true, "step_over key mapped")
assert_eq(has_buf_map("d"), true, "step_into key mapped")
assert_eq(has_buf_map("r"), true, "step_out key mapped")
assert_eq(has_buf_map("q"), true, "terminate key mapped")

-- test 4: toggle exits debug mode
td.toggle()
assert_eq(td.active(), false, "inactive after second toggle")

-- test 5: keymaps are removed
assert_eq(has_buf_map("c"), false, "continue key removed")
assert_eq(has_buf_map("s"), false, "step_over key removed")
assert_eq(has_buf_map("q"), false, "terminate key removed")

print("ALL MODE TESTS PASSED")
