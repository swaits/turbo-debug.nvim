-- tests for adapter loader and path resolution
local loader = require("tiny-debugger.adapters.init")

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("FAIL: %s — expected %s, got %s", msg, vim.inspect(b), vim.inspect(a)))
  end
end

-- test 1: find_executable returns nil for non-existent binaries
assert_eq(loader.find_executable({ "totally-fake-binary-xyz" }), nil, "non-existent binary returns nil")

-- test 2: find_executable finds common system binaries
local found = loader.find_executable({ "sh" })
assert_eq(found ~= nil, true, "find_executable finds sh")

-- test 3: python adapter module loads and has register function
local py = require("tiny-debugger.adapters.python")
assert_eq(type(py.register), "function", "python adapter has register()")

-- test 4: go adapter module loads and has register function
local go = require("tiny-debugger.adapters.go")
assert_eq(type(go.register), "function", "go adapter has register()")

-- test 5: register doesn't override existing adapter
local dap = require("dap")
dap.adapters.test_adapter = { type = "executable", command = "test" }
loader.register(dap, "test_adapter", { type = "executable", command = "new" }, {}, {})
assert_eq(dap.adapters.test_adapter.command, "test", "register doesn't override existing")
dap.adapters.test_adapter = nil

-- test 6: register sets adapter and configs for new adapter
loader.register(dap, "test_new", { type = "executable", command = "test" }, {
  { type = "test_new", request = "launch", name = "test" },
}, { "testlang" })
assert_eq(dap.adapters.test_new.command, "test", "new adapter registered")
assert_eq(#dap.configurations.testlang, 1, "configs registered for filetype")
-- cleanup
dap.adapters.test_new = nil
dap.configurations.testlang = nil

print("ALL ADAPTER TESTS PASSED")
