local M = {}

M.defaults = {
  endpoint = "http://127.0.0.1:57321",
  enabled = true,
  restore_on_insert = true,
  force_english_on_insert_leave = true,
  force_english_on_cmdline_enter = true,
  debug = false,
  banner = {
    enabled = true,
    -- "bottomright" | "bottomleft" | "topright" | "topleft"
    position = "bottomright",
    -- distance (in cells) from the chosen edge
    padding_row = 2,
    padding_col = 2,
    interval_ms = 250,
    flash_ms = 500,
    border = "rounded", -- any value accepted by nvim_open_win's `border` option
    -- Label set: "text" (EN/한/あ/中) or "flag" (🇺🇸/🇰🇷/🇯🇵/🇨🇳).
    -- Override individual labels via `labels` (merged on top of the preset).
    style = "text",
    labels = {}, -- e.g. { korean = "🇰🇷", english = "🇬🇧" }
    -- For position = "sign": extmark priority. Default 200 wins over most sign
    -- plugins (gitsigns ≈ 6). Lower it (e.g. 5) to defer to gitsigns when both
    -- want the same line's sign slot.
    sign_priority = 200,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
