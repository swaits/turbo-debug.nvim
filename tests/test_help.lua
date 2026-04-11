-- tests for help box
local help = require("tiny-debugger.help")
local config = require("tiny-debugger.config")

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("FAIL: %s — expected %s, got %s", msg, vim.inspect(b), vim.inspect(a)))
  end
end

-- test 1: open creates a valid window
help.open()
assert_eq(help.is_open(), true, "help window is open")

-- test 2: close removes the window
help.close()
assert_eq(help.is_open(), false, "help window is closed")

-- test 3: remapped key shows in help content
config.merge({ keys = { continue = "g" } })
help.open()
-- read the buffer content
local wins = vim.api.nvim_list_wins()
local found_g = false
for _, w in ipairs(wins) do
  local buf = vim.api.nvim_win_get_buf(w)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:find("g%s+Continue") then
      found_g = true
    end
  end
end
assert_eq(found_g, true, "remapped key 'g' appears in help")
help.close()

-- reset config
config.merge({})

print("ALL HELP TESTS PASSED")
