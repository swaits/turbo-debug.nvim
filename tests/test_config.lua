local assert_eq = require("helpers").assert_eq
local config = require("turbo-debug.config")

-- defaults unchanged after empty merge
local opts = config.merge({})
assert_eq(opts.keys.continue, "c", "default continue key")
assert_eq(opts.keys.breakpoint, "x", "default modal breakpoint key")
assert_eq(opts.global_keys.toggle, "<leader>dd", "default toggle key")
assert_eq(opts.global_keys.breakpoint, "<leader>dx", "default global breakpoint key")
assert_eq(opts.help_on_enter, true, "default help_on_enter")
assert_eq(opts.quit_exits_mode, true, "default quit_exits_mode")

-- partial key override
opts = config.merge({ keys = { continue = "g" } })
assert_eq(opts.keys.continue, "g", "overridden continue key")
assert_eq(opts.keys.step_over, "s", "preserved step_over key")

-- disable a key with false
opts = config.merge({ keys = { continue = false } })
assert_eq(opts.keys.continue, false, "disabled continue key")

-- global key override
opts = config.merge({ global_keys = { toggle = "<leader>D" } })
assert_eq(opts.global_keys.toggle, "<leader>D", "overridden toggle key")
assert_eq(opts.global_keys.breakpoint, "<leader>dx", "preserved breakpoint key")

-- quit_exits_mode override
opts = config.merge({ quit_exits_mode = false })
assert_eq(opts.quit_exits_mode, false, "overridden quit_exits_mode")

-- merge doesn't mutate defaults
config.merge({ keys = { continue = "z" } })
assert_eq(config.defaults.keys.continue, "c", "defaults not mutated")

print("ALL CONFIG TESTS PASSED")
