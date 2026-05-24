local config = require("kovim.config")
local client = require("kovim.client")
local banner = require("kovim.banner")

local M = {}

local group = vim.api.nvim_create_augroup("KovimIME", { clear = true })

function M.setup(opts)
  config.setup(opts)

  vim.api.nvim_clear_autocmds({ group = group })

  if config.options.force_english_on_insert_leave then
    vim.api.nvim_create_autocmd("InsertLeave", {
      group = group,
      callback = function()
        client.normal()
        banner.hide()
      end,
      desc = "KoVim: switch IME to English after leaving insert mode",
    })
  end

  if config.options.restore_on_insert then
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = group,
      callback = function()
        client.insert()
        banner.show()
      end,
      desc = "KoVim: restore previous IME when entering insert mode",
    })
  elseif config.options.banner and config.options.banner.enabled then
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = group,
      callback = function() banner.show() end,
      desc = "KoVim: show IME banner on insert",
    })
    vim.api.nvim_create_autocmd("InsertLeave", {
      group = group,
      callback = function() banner.hide() end,
      desc = "KoVim: hide IME banner on insert leave",
    })
  end

  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function() banner.refresh_position() end,
    desc = "KoVim: reposition IME banner on resize",
  })

  if config.options.banner and config.options.banner.enabled
      and banner.is_cursor_follow() then
    vim.api.nvim_create_autocmd("CursorMovedI", {
      group = group,
      callback = function() banner.refresh_position() end,
      desc = "KoVim: follow cursor with IME banner",
    })
  end

  if config.options.force_english_on_cmdline_enter then
    vim.api.nvim_create_autocmd("CmdlineEnter", {
      group = group,
      callback = function()
        client.normal()
      end,
      desc = "KoVim: switch IME to English for command-line mode",
    })
  end

  vim.api.nvim_create_user_command("KovimEnglish", function()
    client.english()
  end, { desc = "KoVim: immediately switch IME to English" })

  vim.api.nvim_create_user_command("KovimRestore", function()
    client.restore()
  end, { desc = "KoVim: restore previous IME" })

  vim.api.nvim_create_user_command("KovimHealth", function()
    client.health()
  end, { desc = "KoVim: diagnose agent connectivity and autocmd setup" })
end

return M
