-- tests for persistent breakpoints
local td = require("tiny-debugger")
td.setup()

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("FAIL: %s — expected %s, got %s", msg, vim.inspect(b), vim.inspect(a)))
  end
end

-- test 1: global x mapping exists
local maparg = vim.fn.maparg("x", "n", false, true)
assert_eq(maparg.desc, "tiny-debugger: toggle breakpoint", "global x mapping exists")

-- test 2: global X mapping exists
maparg = vim.fn.maparg("X", "n", false, true)
assert_eq(maparg.desc, "tiny-debugger: conditional breakpoint", "global X mapping exists")

-- test 3: persistent-breakpoints API is callable
local api = require("persistent-breakpoints.api")
assert_eq(type(api.toggle_breakpoint), "function", "toggle_breakpoint is a function")
assert_eq(type(api.set_conditional_breakpoint), "function", "set_conditional_breakpoint is a function")

print("ALL BREAKPOINT TESTS PASSED")
