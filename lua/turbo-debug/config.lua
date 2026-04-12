local M = {}

M.defaults = {
  help_on_enter = true,
  builtin_adapters = true,
  quit_exits_mode = true, -- q terminates AND exits debug mode (false = terminate only)
  -- When `c` is pressed with no breakpoints set, launch the first adapter
  -- configuration for the filetype with stopOnEntry so the debugger pauses
  -- at the program's entry point. Matches the Turbo Pascal "press key to
  -- start debugging" model. Set false to always run until a breakpoint.
  stop_on_entry_when_no_breakpoints = true,

  -- modal keys (active only during debug mode, single-key)
  keys = {
    continue = "c",
    step_over = "s",
    step_into = "d",
    step_out = "r",
    run_to_cursor = "C",
    breakpoint = "x",
    cond_breakpoint = "X",
    clear_breakpoints = "D",
    watch = "W",
    hover = "K",
    eval = "E",
    terminate = "q",
    restart = "R",
    help = "?",
  },

  -- global keys (always available, <leader>d prefix)
  global_keys = {
    toggle = "<leader>dd",
    breakpoint = "<leader>dx",
    cond_breakpoint = "<leader>dX",
    clear_breakpoints = "<leader>dD",
  },

  -- sidebar position: "left" (default) or "right"
  sidebar = "left",

  -- highlight the active dapui pane's border/separator vs. dim inactive panes
  active_window_highlight = true,

  dapui = {
    -- Unicode icons via byte escapes so they survive tool round-trips.
    -- ▾ U+25BE down-triangle (expanded), ▸ U+25B8 right-triangle (collapsed),
    -- ▶ U+25B6 right-pointing triangle (current frame / play-head)
    icons = {
      expanded      = "\xe2\x96\xbe",
      collapsed     = "\xe2\x96\xb8",
      current_frame = "\xe2\x96\xb6",
    },
    controls = {
      enabled = true,
      element = "repl",
      -- ▶ play, ⏸ pause, ⤓ step-into, ⇒ step-over, ⤒ step-out, ↶ step-back,
      -- ↻ run-last, ■ terminate, ⊗ disconnect
      icons = {
        play       = "\xe2\x96\xb6",
        pause      = "\xe2\x8f\xb8",
        step_into  = "\xe2\xa4\x93",
        step_over  = "\xe2\x87\x92",
        step_out   = "\xe2\xa4\x92",
        step_back  = "\xe2\x86\xb6",
        run_last   = "\xe2\x86\xbb",
        terminate  = "\xe2\x96\xa0",
        disconnect = "\xe2\x8a\x97",
      },
    },
    floating = { border = "rounded", mappings = { close = { "q", "<Esc>" } } },
    render = { indent = 2, max_type_length = 20 },
    -- layouts are built dynamically from `sidebar` in mode.lua; override
    -- `layouts` here to fully customize.
    layouts = nil,
  },

  virtual_text = {
    enabled = true,
    commented = true,
    virt_text_pos = "eol",
    show_stop_reason = true,
    highlight_changed_variables = true,
    highlight_new_as_changed = false,
    only_first_definition = false,
    all_frames = false,
    display_callback = function(variable)
      if #variable.value > 80 then return " = " .. variable.value:sub(1, 77) .. "…" end
      return " = " .. variable.value
    end,
  },

  adapters = {},
}

M.opts = M.defaults

function M.merge(user_opts)
  M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_opts or {})
  if user_opts then
    for _, tbl_name in ipairs({ "keys", "global_keys" }) do
      if user_opts[tbl_name] then
        for k, v in pairs(user_opts[tbl_name]) do
          if v == false then M.opts[tbl_name][k] = false end
        end
      end
    end
  end
  return M.opts
end

return M
