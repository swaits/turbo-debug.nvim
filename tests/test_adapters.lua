local assert_eq = require("helpers").assert_eq
local loader = require("turbo-debug.adapters.init")
local dap = require("dap")

-- find_executable returns nil for non-existent binaries
assert_eq(loader.find_executable({ "totally-fake-binary-xyz" }), nil, "non-existent binary returns nil")

-- find_executable finds common system binaries
assert_eq(loader.find_executable({ "sh" }) ~= nil, true, "find_executable finds sh")

-- all adapter modules load and have register()
for _, name in ipairs({ "python", "go", "c", "javascript", "dart", "bash", "r" }) do
  assert_eq(type(require("turbo-debug.adapters." .. name).register), "function", name .. " has register()")
end

-- register doesn't override existing adapter
dap.adapters.test_adapter = { type = "executable", command = "test" }
loader.register(dap, "test_adapter", { type = "executable", command = "new" }, {}, {})
assert_eq(dap.adapters.test_adapter.command, "test", "register doesn't override existing")
dap.adapters.test_adapter = nil

-- register sets adapter and configs for new adapter
loader.register(dap, "test_new", { type = "executable", command = "test" }, {
  { type = "test_new", request = "launch", name = "test" },
}, { "testlang" })
assert_eq(dap.adapters.test_new.command, "test", "new adapter registered")
assert_eq(#dap.configurations.testlang, 1, "configs registered for filetype")
dap.adapters.test_new = nil
dap.configurations.testlang = nil

print("ALL ADAPTER TESTS PASSED")
