local M = {}

M.configs = {
  options = {
    prompt_pattern = '',
    history_filepath = '',
    history_filter = function(_) return true end,
    cleanup_key_sequence = '<C-k><C-u>',
    floating_border = 'rounded',
    edit_filetype = 'bash',
    edit_win_options = {},
    hooks = {
      init_terminal = nil
    },
  }
}

function M.setup(configs)
  M.configs = vim.tbl_deep_extend('force', M.configs, configs)
end

return M
