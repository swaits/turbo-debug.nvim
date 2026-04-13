local M = {}

function M.assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("FAIL: %s — expected %s, got %s", msg, vim.inspect(b), vim.inspect(a)))
  end
end

function M.assert_true(v, msg)
  if not v then
    error(string.format("FAIL: %s — expected truthy, got %s", msg, vim.inspect(v)))
  end
end

function M.assert_false(v, msg)
  if v then
    error(string.format("FAIL: %s — expected falsy, got %s", msg, vim.inspect(v)))
  end
end

return M
