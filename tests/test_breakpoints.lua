local assert_eq = require("helpers").assert_eq
local td = require("tiny-debugger")
td.setup()

-- global <leader>x mapping exists
assert_eq(vim.fn.maparg("<leader>x", "n", false, true).desc, "tiny-debugger: toggle breakpoint", "global <leader>x mapping")

-- global <leader>X mapping exists
assert_eq(vim.fn.maparg("<leader>X", "n", false, true).desc, "tiny-debugger: conditional breakpoint", "global <leader>X mapping")

-- persistent-breakpoints API is callable
local api = require("persistent-breakpoints.api")
assert_eq(type(api.toggle_breakpoint), "function", "toggle_breakpoint is a function")
assert_eq(type(api.set_conditional_breakpoint), "function", "set_conditional_breakpoint is a function")

print("ALL BREAKPOINT TESTS PASSED")
