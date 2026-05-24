local config = require("kovim.config")

local M = {}

local state = {
  win = nil,
  buf = nil,
  timer = nil,
  ns = vim.api.nvim_create_namespace("KovimBanner"),
  inline_ns = vim.api.nvim_create_namespace("KovimBannerInline"),
  inline_buf = nil,
  last_ime = nil,
  flash_until = 0,
  in_flight = false,
  active = false,
}

local EXTMARK_POSITIONS = {
  inline = true, right_align = true, left_align = true,
  sign = true, numhl = true,
}

local function uses_extmark(pos)
  pos = pos or (config.options.banner or {}).position
  return EXTMARK_POSITIONS[pos] == true
end

function M.is_cursor_follow(pos)
  pos = pos or (config.options.banner or {}).position
  return pos == "cursor" or uses_extmark(pos)
end

local function effective_hl(hl)
  if vim.uv.now() < state.flash_until then
    return "KovimBannerChanged"
  end
  return hl
end

-- ── language classification ──────────────────────────────────────────────────

local LABEL_PRESETS = {
  text = {
    english = "EN", korean = "한", japanese = "あ", chinese = "中", unknown = "?",
  },
  flag = {
    english = "🇺🇸", korean = "🇰🇷", japanese = "🇯🇵", chinese = "🇨🇳", unknown = "🏳",
  },
}

local function get_labels()
  local opts = config.options.banner or {}
  local preset = LABEL_PRESETS[opts.style or "text"] or LABEL_PRESETS.text
  return vim.tbl_extend("force", preset, opts.labels or {})
end

local function classify(id)
  local labels = get_labels()
  if not id or id == "" then
    return { label = labels.unknown, hl = "KovimBannerUnknown" }
  end
  local lower = id:lower()
  if lower:find("korean") or lower:find("hangul")
      or lower:find("2set") or lower:find("3set") then
    return { label = labels.korean, hl = "KovimBannerKorean" }
  end
  if lower:find("japanese") or lower:find("kotoeri")
      or lower:find("hiragana") or lower:find("katakana") or lower:find("romaji") then
    return { label = labels.japanese, hl = "KovimBannerJapanese" }
  end
  if lower:find("chinese") or lower:find("pinyin") or lower:find("zhuyin")
      or lower:find("cangjie") or lower:find("sucheng") then
    return { label = labels.chinese, hl = "KovimBannerChinese" }
  end
  return { label = labels.english, hl = "KovimBannerEnglish" }
end

-- ── highlight groups (overridable by user) ───────────────────────────────────

local function ensure_highlights()
  local sets = {
    KovimBannerEnglish  = { fg = "#a6e3a1", bold = true },
    KovimBannerKorean   = { fg = "#f9e2af", bold = true },
    KovimBannerJapanese = { fg = "#f5c2e7", bold = true },
    KovimBannerChinese  = { fg = "#fab387", bold = true },
    KovimBannerUnknown  = { fg = "#9399b2" },
    KovimBannerChanged  = { fg = "#1e1e2e", bg = "#f38ba8", bold = true },
  }
  for name, attrs in pairs(sets) do
    attrs.default = true
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

-- ── window management ────────────────────────────────────────────────────────

-- Compute the floating-window placement.
-- Returns a partial nvim_open_win opts table (relative/row/col/anchor[/win]).
local function placement(width)
  local opts = config.options.banner or {}
  local pos = opts.position or "bottomright"
  local pad_row = opts.padding_row or 2
  local pad_col = opts.padding_col or 2

  if pos == "cursor" then
    -- Anchor to the cursor: appear at the start of the line text area
    -- (right after the line-number / sign / fold gutter) on the cursor's line.
    local cur_win = vim.api.nvim_get_current_win()
    local screen_row = vim.fn.winline() - 1
    local info = vim.fn.getwininfo(cur_win)[1] or {}
    local gutter = info.textoff or 0
    return {
      relative = "win",
      win = cur_win,
      row = screen_row,
      col = gutter + pad_col,
      anchor = "NW",
    }
  end

  -- Editor-relative anchors.
  local bottom_row = vim.o.lines - vim.o.cmdheight - 2 - pad_row
  local right_col = vim.o.columns - width - 1 - pad_col
  local center_col = math.floor((vim.o.columns - width) / 2)

  local row, col
  if pos == "topleft" then
    row, col = pad_row + 1, pad_col + 1
  elseif pos == "topright" then
    row, col = pad_row + 1, right_col
  elseif pos == "topcenter" then
    row, col = pad_row + 1, center_col
  elseif pos == "bottomleft" then
    row, col = bottom_row, pad_col + 1
  elseif pos == "bottomcenter" then
    row, col = bottom_row, center_col
  else -- bottomright (default)
    row, col = bottom_row, right_col
  end
  if row < 0 then row = 0 end
  if col < 0 then col = 0 end
  return { relative = "editor", row = row, col = col, anchor = "NW" }
end

local function ensure_window(width)
  if state.buf == nil or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden = "wipe"
  end
  local opts = config.options.banner or {}
  local win_opts = placement(width)
  win_opts.width = width
  win_opts.height = 1
  win_opts.style = "minimal"
  win_opts.focusable = false
  win_opts.zindex = 200
  win_opts.border = opts.border or "rounded"
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, win_opts)
    return
  end
  win_opts.noautocmd = true
  state.win = vim.api.nvim_open_win(state.buf, false, win_opts)
  vim.wo[state.win].winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder"
end

local function render_float(label, hl)
  ensure_highlights()
  local text = " " .. label .. " "
  ensure_window(#text)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { text })
  vim.api.nvim_buf_clear_namespace(state.buf, state.ns, 0, -1)
  vim.api.nvim_buf_set_extmark(state.buf, state.ns, 0, 0, {
    end_row = 0,
    end_col = #text,
    hl_group = effective_hl(hl),
  })
end

local function clear_inline()
  if state.inline_buf and vim.api.nvim_buf_is_valid(state.inline_buf) then
    vim.api.nvim_buf_clear_namespace(state.inline_buf, state.inline_ns, 0, -1)
  end
  state.inline_buf = nil
end

local function render_inline(label, hl)
  ensure_highlights()
  local opts = config.options.banner or {}
  local buf = vim.api.nvim_get_current_buf()
  if state.inline_buf and state.inline_buf ~= buf
      and vim.api.nvim_buf_is_valid(state.inline_buf) then
    vim.api.nvim_buf_clear_namespace(state.inline_buf, state.inline_ns, 0, -1)
  end
  state.inline_buf = buf
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local line_count = vim.api.nvim_buf_line_count(buf)
  if row >= line_count then row = line_count - 1 end
  if row < 0 then row = 0 end
  vim.api.nvim_buf_clear_namespace(buf, state.inline_ns, 0, -1)
  local hl_use = effective_hl(hl)
  local mark = {
    hl_mode = "combine",
    priority = opts.sign_priority or 200,
  }
  if opts.position == "sign" then
    -- Lives in the sign column (the gap between the line-number gutter and
    -- the text area). Must be at most 2 cells wide; pad or trim to fit.
    local cells = vim.fn.strdisplaywidth(label)
    local sign_text = label
    if cells < 2 then
      sign_text = label .. string.rep(" ", 2 - cells)
    elseif cells > 2 then
      sign_text = vim.fn.strcharpart(label, 0, 2)
    end
    mark.sign_text = sign_text
    mark.sign_hl_group = hl_use
  elseif opts.position == "numhl" then
    -- Color the line-number on the cursor line with the language color.
    -- No label is rendered, but it never competes with sign-column plugins
    -- (e.g. gitsigns). Requires `set number` to be visible.
    mark.number_hl_group = hl_use
  else
    local prefix = opts.inline_prefix or "  "
    local text = prefix .. label
    mark.virt_text = { { text, hl_use } }
    if opts.position == "right_align" then
      mark.virt_text_pos = "right_align"
    elseif opts.position == "left_align" then
      -- Overlay at column 0 of the cursor line; covers existing characters.
      mark.virt_text_pos = "overlay"
      mark.virt_text_win_col = 0
    else
      mark.virt_text_pos = "eol"
    end
  end
  vim.api.nvim_buf_set_extmark(buf, state.inline_ns, row, 0, mark)
end

local function render(label, hl)
  if uses_extmark() then
    render_inline(label, hl)
  else
    render_float(label, hl)
  end
end

-- ── polling ──────────────────────────────────────────────────────────────────

local function apply(ime)
  if not state.active then return end
  local info = classify(ime)
  if state.last_ime ~= nil and state.last_ime ~= ime then
    local flash_ms = (config.options.banner and config.options.banner.flash_ms) or 500
    state.flash_until = vim.uv.now() + flash_ms
  end
  state.last_ime = ime
  render(info.label, info.hl)
end

local function poll()
  if state.in_flight then return end
  state.in_flight = true
  local args = { "curl", "-fsS", "--max-time", "0.5", config.options.endpoint .. "/health" }
  vim.system(args, { text = true }, function(result)
    -- This callback runs in the libuv fast event-loop; defer all API calls.
    vim.schedule(function()
      state.in_flight = false
      if result.code ~= 0 then return end
      local ok, parsed = pcall(vim.fn.json_decode, result.stdout or "")
      if not ok or type(parsed) ~= "table" then return end
      apply(parsed.currentInputSourceId)
    end)
  end)
end

-- ── public API ───────────────────────────────────────────────────────────────

function M.show()
  local opts = config.options.banner
  if not (opts and opts.enabled) then return end
  state.active = true
  state.last_ime = nil
  state.flash_until = 0
  render("…", "KovimBannerUnknown")
  poll()
  if state.timer then
    state.timer:stop()
    state.timer:close()
  end
  state.timer = vim.uv.new_timer()
  local interval = opts.interval_ms or 250
  state.timer:start(interval, interval, vim.schedule_wrap(poll))
end

function M.hide()
  state.active = false
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.buf = nil
  clear_inline()
end

function M.refresh_position()
  if not state.active then return end
  if uses_extmark() then
    if state.last_ime ~= nil then
      local info = classify(state.last_ime)
      render_inline(info.label, info.hl)
    else
      render_inline("…", "KovimBannerUnknown")
    end
    return
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) and state.buf then
    local lines = vim.api.nvim_buf_get_lines(state.buf, 0, 1, false)
    local width = (lines[1] and #lines[1]) or 4
    ensure_window(width)
  end
end

return M
