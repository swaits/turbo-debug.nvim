local assert_eq = require("helpers").assert_eq
local config = require("tiny-debugger.config")

-- defaults unchanged after empty merge
local opts = config.merge({})
assert_eq(opts.keys.continue, "c", "default continue key")
assert_eq(opts.help_on_enter, true, "default help_on_enter")
assert_eq(opts.builtin_adapters, true, "default builtin_adapters")

-- partial key override
opts = config.merge({ keys = { continue = "g" } })
assert_eq(opts.keys.continue, "g", "overridden continue key")
assert_eq(opts.keys.step_over, "s", "preserved step_over key")
assert_eq(opts.keys.terminate, "q", "preserved terminate key")

-- disable a key with false
opts = config.merge({ keys = { continue = false } })
assert_eq(opts.keys.continue, false, "disabled continue key")
assert_eq(opts.keys.step_over, "s", "preserved step_over after disable")

-- override help_on_enter
opts = config.merge({ help_on_enter = false })
assert_eq(opts.help_on_enter, false, "overridden help_on_enter")
assert_eq(opts.keys.continue, "c", "keys preserved after help override")

-- merge doesn't mutate defaults
config.merge({ keys = { continue = "z" } })
assert_eq(config.defaults.keys.continue, "c", "defaults not mutated")

print("ALL CONFIG TESTS PASSED")
