local assert_eq = require("helpers").assert_eq
local td = require("tiny-debugger")
td.setup()

-- global x mapping exists
assert_eq(vim.fn.maparg("x", "n", false, true).desc, "tiny-debugger: toggle breakpoint", "global x mapping")

-- global X mapping exists
assert_eq(vim.fn.maparg("X", "n", false, true).desc, "tiny-debugger: conditional breakpoint", "global X mapping")

-- persistent-breakpoints API is callable
local api = require("persistent-breakpoints.api")
assert_eq(type(api.toggle_breakpoint), "function", "toggle_breakpoint is a function")
assert_eq(type(api.set_conditional_breakpoint), "function", "set_conditional_breakpoint is a function")

print("ALL BREAKPOINT TESTS PASSED")
