local M = {}

M.defaults = {
  help_on_enter = true,
  builtin_adapters = true,

  -- modal keys (active only during debug mode, single-key)
  keys = {
    continue = "c",
    step_over = "s",
    step_into = "d",
    step_out = "r",
    run_to_cursor = "C",
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

  dapui = {
    icons = { expanded = "▼", collapsed = "▶", current_frame = "➤" },
    controls = {
      enabled = true,
      element = "repl",
    },
    floating = { border = "rounded" },
    render = { indent = 2, max_type_length = 20 },
    layouts = {
      {
        position = "right",
        size = 40,
        elements = {
          { id = "scopes", size = 0.50 },
          { id = "watches", size = 0.25 },
          { id = "stacks", size = 0.25 },
        },
      },
      {
        position = "bottom",
        size = 12,
        elements = {
          { id = "repl", size = 0.50 },
          { id = "console", size = 0.50 },
        },
      },
    },
  },

  virtual_text = {
    commented = true,
    highlight_changed_variables = true,
    only_first_definition = false,
    all_frames = false,
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
