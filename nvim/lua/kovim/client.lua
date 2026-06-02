local config = require("kovim.config")

local M = {}

-- ── helpers ──────────────────────────────────────────────────────────────────

local function log(msg)
  if config.options.debug then
    vim.schedule(function()
      vim.notify("kovim: " .. msg, vim.log.levels.DEBUG)
    end)
  end
end

-- Async fire-and-forget HTTP POST using curl.
-- Returns immediately; errors are printed only in debug mode.
local function post_async(path)
  local url = config.options.endpoint .. path
  local args = { "curl", "-fsS", "-X", "POST", "--max-time", "0.5", url }

  if vim.system then
    -- Neovim 0.10+
    vim.system(args, { text = true }, function(result)
      if result.code ~= 0 then
        log("POST " .. path .. " failed (code=" .. result.code .. "): " .. (result.stderr or ""))
      end
    end)
  else
    vim.fn.jobstart(args, {
      detach = true,
      on_stderr = function(_, data)
        if data and #data > 0 then
          log("POST " .. path .. " stderr: " .. table.concat(data, "\n"))
        end
      end,
    })
  end
end

-- Synchronous GET; returns parsed table or nil on error.
local function get_sync(path)
  local url = config.options.endpoint .. path
  local result = vim.fn.system({ "curl", "-fsS", "--max-time", "1", url })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local ok, parsed = pcall(vim.fn.json_decode, result)
  if ok then
    return parsed
  end
  return nil
end

-- ── public API ───────────────────────────────────────────────────────────────

function M.normal()
  if not config.options.enabled then return end
  log("→ /mode/normal")
  post_async("/mode/normal")
end

function M.insert()
  if not config.options.enabled then return end
  if not config.options.restore_on_insert then return end
  log("→ /mode/insert")
  post_async("/mode/insert")
end

function M.english()
  post_async("/ime/english")
end

function M.restore()
  post_async("/ime/restore")
end

-- ── health check ─────────────────────────────────────────────────────────────

function M.health()
  local lines = {}
  local function add(icon, msg) table.insert(lines, icon .. " " .. msg) end

  -- 1. check if curl is available
  local curl_check = vim.fn.system({ "curl", "--version" })
  if vim.v.shell_error ~= 0 then
    add("✗", "curl not found in PATH — install curl and restart Neovim")
  else
    local version = curl_check:match("curl%s+([%d%.]+)")
    add("✓", "curl " .. (version or "found"))
  end

  -- 2. check if the kovim CLI is available (optional but nice)
  local im_check = vim.fn.system({ "kovim", "current" })
  if vim.v.shell_error ~= 0 then
    add("⚠", "kovim CLI not found in PATH (optional, used for diagnostics)")
  else
    local ime = vim.trim(im_check)
    add("✓", "kovim CLI found, current IME: " .. ime)
  end

  -- 3. check if agent is reachable
  local status = get_sync("/health")
  if status == nil then
    add("✗", "kovim-agent not reachable at " .. config.options.endpoint)
    add("  ", "→ Is KoVim.app running? Check the menu bar for the ⌨︎ KoVim icon.")
  else
    add("✓", "kovim-agent reachable at " .. config.options.endpoint)
    if status.currentInputSourceId then
      add("  ", "current IME:  " .. status.currentInputSourceId)
    end
    if status.previousInputSourceId then
      add("  ", "previous IME: " .. status.previousInputSourceId)
    else
      add("  ", "previous IME: (none — will be set after first Esc from Korean insert)")
    end
    if status.englishInputSourceId then
      add("  ", "english IME:  " .. status.englishInputSourceId)
    end
  end

  -- 4. check autocmds are registered
  local autocmds = vim.api.nvim_get_autocmds({ group = "KovimIME" })
  if #autocmds == 0 then
    add("✗", "KovimIME autocmds not registered — setup() was not called properly")
  else
    add("✓", #autocmds .. " autocmd(s) registered (KovimIME group)")
    for _, ac in ipairs(autocmds) do
      add("  ", "· " .. ac.event .. (ac.desc and (": " .. ac.desc:gsub("KoVim: ", "")) or ""))
    end
  end

  -- 5. show current config
  add("", "")
  add("⚙", "current config:")
  add("  ", "endpoint:                      " .. config.options.endpoint)
  add("  ", "restore_on_insert:             " .. tostring(config.options.restore_on_insert))
  add("  ", "force_english_on_insert_leave: " .. tostring(config.options.force_english_on_insert_leave))
  add("  ", "force_english_on_cmdline_enter:" .. tostring(config.options.force_english_on_cmdline_enter))
  add("  ", "debug:                         " .. tostring(config.options.debug))

  -- Print all lines
  for _, line in ipairs(lines) do
    print(line)
  end
end

return M
