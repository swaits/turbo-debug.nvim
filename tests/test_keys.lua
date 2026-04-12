local assert_eq = require("helpers").assert_eq
local td = require("turbo-debug")

-- set a custom mapping for 'c'
vim.keymap.set("n", "c", function() end, { buffer = 0, desc = "custom c" })

-- verify custom mapping exists
local maparg = vim.fn.maparg("c", "n", false, true)
assert_eq(maparg.desc, "custom c", "custom mapping exists before enter")

-- enter debug mode — should override 'c'
td.toggle()
maparg = vim.fn.maparg("c", "n", false, true)
assert_eq(maparg.desc, "turbo-debug: continue", "c overridden in debug mode")

-- exit debug mode — should restore custom 'c'
td.toggle()
maparg = vim.fn.maparg("c", "n", false, true)
assert_eq(maparg.desc, "custom c", "custom mapping restored after exit")

print("ALL KEY STASH/RESTORE TESTS PASSED")
