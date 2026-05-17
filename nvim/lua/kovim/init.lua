local config = require("kovim.config")
local client = require("kovim.client")

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
      end,
      desc = "KoVim: switch IME to English after leaving insert mode",
    })
  end

  if config.options.restore_on_insert then
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = group,
      callback = function()
        client.insert()
      end,
      desc = "KoVim: restore previous IME when entering insert mode",
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
