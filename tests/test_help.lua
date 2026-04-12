local assert_eq = require("helpers").assert_eq
local help = require("turbo-debug.help")
local config = require("turbo-debug.config")

-- open creates a valid window
help.open()
assert_eq(help.is_open(), true, "help window is open")

-- close removes the window
help.close()
assert_eq(help.is_open(), false, "help window is closed")

-- remapped key shows in help content
config.merge({ keys = { continue = "g" } })
help.open()
local found_g = false
for _, w in ipairs(vim.api.nvim_list_wins()) do
  for _, line in ipairs(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)) do
    if line:find("g%s+Continue") then found_g = true end
  end
end
assert_eq(found_g, true, "remapped key 'g' appears in help")
help.close()
config.merge({})

print("ALL HELP TESTS PASSED")
