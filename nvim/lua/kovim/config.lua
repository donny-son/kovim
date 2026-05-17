local M = {}

M.defaults = {
  endpoint = "http://127.0.0.1:57321",
  enabled = true,
  restore_on_insert = true,
  force_english_on_insert_leave = true,
  force_english_on_cmdline_enter = true,
  debug = false,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
