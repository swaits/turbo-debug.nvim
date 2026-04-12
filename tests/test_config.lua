local assert_eq = require("helpers").assert_eq
local config = require("turbo-debug.config")

-- defaults unchanged after empty merge
local opts = config.merge({})
assert_eq(opts.keys.continue, "c", "default continue key")
assert_eq(opts.keys.breakpoint, "x", "default modal breakpoint key")
assert_eq(opts.global_keys.toggle, "<leader>dd", "default toggle key")
assert_eq(opts.global_keys.breakpoint, "<leader>dx", "default global breakpoint key")
assert_eq(opts.help_on_enter, false, "default help_on_enter")
assert_eq(opts.stop_on_entry_when_no_breakpoints, true, "default stop_on_entry_when_no_breakpoints")
assert_eq(opts.max_value_width, 2000, "default max_value_width")
assert_eq(opts.console_refresh_ms, 50, "default console_refresh_ms")

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

-- max_value_width override
opts = config.merge({ max_value_width = 0 })
assert_eq(opts.max_value_width, 0, "overridden max_value_width")

-- merge doesn't mutate defaults
config.merge({ keys = { continue = "z" } })
assert_eq(config.defaults.keys.continue, "c", "defaults not mutated")

print("ALL CONFIG TESTS PASSED")
