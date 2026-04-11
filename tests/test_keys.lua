-- tests for keybinding stash/restore
local td = require("tiny-debugger")

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("FAIL: %s — expected %s, got %s", msg, vim.inspect(b), vim.inspect(a)))
  end
end

-- set a custom mapping for 'c'
local custom_called = false
vim.keymap.set("n", "c", function() custom_called = true end, { buffer = 0, desc = "custom c" })

-- verify custom mapping exists
local maparg = vim.fn.maparg("c", "n", false, true)
assert_eq(maparg.desc, "custom c", "custom mapping exists before enter")

-- enter debug mode — should override 'c'
td.toggle()
maparg = vim.fn.maparg("c", "n", false, true)
assert_eq(maparg.desc, "tiny-debugger: continue", "c overridden in debug mode")

-- exit debug mode — should restore custom 'c'
td.toggle()
maparg = vim.fn.maparg("c", "n", false, true)
assert_eq(maparg.desc, "custom c", "custom mapping restored after exit")

print("ALL KEY STASH/RESTORE TESTS PASSED")
