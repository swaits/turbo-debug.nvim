local M = {}

M.defaults = {
  help_on_enter = true,
  builtin_adapters = true,

  keys = {
    continue = "c",
    step_over = "s",
    step_into = "d",
    step_out = "r",
    run_to_cursor = "C",
    breakpoint = "<leader>x",
    cond_breakpoint = "<leader>X",
    watch = "W",
    hover = "K",
    eval = "E",
    terminate = "q",
    restart = "R",
    clear_breakpoints = "<leader>D",
    help = "?",
  },

  dapui = {
    controls = { enabled = false },
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
  if user_opts and user_opts.keys then
    for k, v in pairs(user_opts.keys) do
      if v == false then M.opts.keys[k] = false end
    end
  end
  return M.opts
end

return M
