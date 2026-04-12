local assert_eq = require("helpers").assert_eq
local td = require("tiny-debugger")
td.setup()

-- global breakpoint mappings exist under <leader>d prefix
assert_eq(vim.fn.maparg("<leader>dx", "n", false, true).desc, "Toggle breakpoint", "<leader>dx mapping")
assert_eq(vim.fn.maparg("<leader>dX", "n", false, true).desc, "Conditional breakpoint", "<leader>dX mapping")
assert_eq(vim.fn.maparg("<leader>dD", "n", false, true).desc, "Clear all breakpoints", "<leader>dD mapping")

-- toggle mapping exists
assert_eq(vim.fn.maparg("<leader>dd", "n", false, true).desc, "Toggle debug mode", "<leader>dd mapping")

-- persistent-breakpoints API is callable
local api = require("persistent-breakpoints.api")
assert_eq(type(api.toggle_breakpoint), "function", "toggle_breakpoint is a function")

print("ALL BREAKPOINT TESTS PASSED")
